"""Tests for bin/homelab. Run with: python3 -m unittest discover -s tests -v"""

import contextlib
import importlib.machinery
import importlib.util
import io
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CLI = REPO / "bin" / "homelab"


def load_cli():
    loader = importlib.machinery.SourceFileLoader("homelab_cli", str(CLI))
    spec = importlib.util.spec_from_loader("homelab_cli", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


homelab = load_cli()


class TempRepo:
    """A throwaway checkout with just enough structure for the CLI."""

    def __init__(self, services=None):
        self.dir = Path(tempfile.mkdtemp(prefix="homelab-test-"))
        (self.dir / "bin").mkdir()
        shutil.copy(CLI, self.dir / "bin" / "homelab")
        (self.dir / "services").mkdir()
        for name, compose in (services or {}).items():
            svc = self.dir / "services" / name
            svc.mkdir(parents=True)
            (svc / "docker-compose.yml").write_text(compose)

    def add_env(self, name, values):
        path = self.dir / "services" / name / ".env"
        path.write_text("\n".join(f"{k}={v}" for k, v in values.items()) + "\n")
        path.chmod(0o600)

    def add_template(self, name, text):
        (self.dir / "services" / name / ".env.template").write_text(text)

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)


def run_cli(argv):
    out = io.StringIO()
    err = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = homelab.main(argv)
    return code, out.getvalue(), err.getvalue()


PROXY_COMPOSE = """services:
  edge:
    image: ${PROXY_IMAGE:-traefik:latest}
    ports:
      - "443:443"
    labels:
      - "traefik.http.routers.dash.tls.certresolver=dns"
    command:
      - "--certificatesresolvers.dns.acme.email=${EMAIL}"
"""

APP_COMPOSE = """services:
  app:
    image: ${APP_IMAGE:-example/app:latest}
    environment:
      - TOKEN=${APP_TOKEN}
    labels:
      - "traefik.http.routers.app.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.app.tls.certresolver=dns"
"""


class EnvFileTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_read_env_strips_quotes_and_skips_comments(self):
        path = self.tmp / ".env"
        path.write_text('# a comment\nA=1\nB="two"\n\nC=three=four\n')
        self.assertEqual(
            homelab.read_env(path), {"A": "1", "B": "two", "C": "three=four"}
        )

    def test_read_env_missing_file_is_empty(self):
        self.assertEqual(homelab.read_env(self.tmp / "nope.env"), {})

    def test_write_env_updates_in_place_and_sets_600(self):
        path = self.tmp / ".env"
        path.write_text("# keep me\nA=old\nB=keep\n")
        homelab.write_env(path, {"A": "new", "C": "added"})
        text = path.read_text()
        self.assertIn("# keep me", text)
        self.assertIn("A=new", text)
        self.assertIn("B=keep", text)
        self.assertIn("C=added", text)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_parse_template_keeps_help_text(self):
        path = self.tmp / ".env.template"
        path.write_text("# first line\n# second line\nKEY=value\nOTHER=x\n")
        entries = homelab.parse_template(path)
        self.assertEqual(entries[0]["key"], "KEY")
        self.assertEqual(entries[0]["help"], "first line second line")
        self.assertEqual(entries[1]["help"], "")

    def test_placeholders_are_detected(self):
        self.assertTrue(homelab.is_placeholder("(put your domain here)"))
        self.assertTrue(homelab.is_placeholder("changeme"))
        self.assertFalse(homelab.is_placeholder("cloud.example.com"))

    def test_htpasswd_entry_looks_like_a_hash(self):
        entry = homelab.htpasswd_entry("bob", "s3cret")
        user, _, hashed = entry.partition(":")
        self.assertEqual(user, "bob")
        self.assertTrue(hashed.startswith("$"), hashed)
        self.assertNotIn("s3cret", entry)


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo({"edge": PROXY_COMPOSE, "app": APP_COMPOSE})
        self.addCleanup(self.repo.cleanup)

    def test_find_root_from_a_subdirectory(self):
        previous = Path.cwd()
        try:
            os.chdir(self.repo.dir / "services" / "app")
            self.assertEqual(homelab.find_root(), self.repo.dir.resolve())
        finally:
            os.chdir(previous)

    def test_find_root_prefers_explicit_argument(self):
        self.assertEqual(
            homelab.find_root(str(self.repo.dir)), self.repo.dir.resolve()
        )

    def test_proxy_is_detected_by_the_443_binding(self):
        dirs = homelab.service_dirs(self.repo.dir)
        self.assertEqual(homelab.detect_proxy(dirs), "edge")

    def test_configured_order_comes_after_the_proxy(self):
        dirs = homelab.service_dirs(self.repo.dir)
        conf = {"general": {"order": ["app"]}}
        self.assertEqual(homelab.build_order(dirs, "edge", conf), ["edge", "app"])

    def test_unknown_services_are_still_ordered(self):
        dirs = homelab.service_dirs(self.repo.dir)
        self.assertEqual(homelab.build_order(dirs, "edge", {}), ["edge", "app"])


class UpCommandTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo({"edge": PROXY_COMPOSE, "app": APP_COMPOSE})
        self.addCleanup(self.repo.cleanup)
        self.repo.add_env("app", {"APP_TOKEN": "x", "DOMAIN": "app.example.com"})

    def test_dry_run_starts_the_proxy_first(self):
        code, out, _ = run_cli(["--root", str(self.repo.dir), "up", "--dry-run"])
        self.assertEqual(code, 0)
        edge = out.index(str(self.repo.dir / "services" / "edge"))
        app = out.index(str(self.repo.dir / "services" / "app"))
        self.assertLess(edge, app)
        self.assertIn("up -d", out)

    def test_dry_run_does_not_touch_docker(self):
        code, out, _ = run_cli(["--root", str(self.repo.dir), "up", "--dry-run"])
        self.assertEqual(code, 0)
        self.assertNotIn("inspect", out)

    def test_unknown_service_is_rejected(self):
        code, _, err = run_cli(["--root", str(self.repo.dir), "up", "ghost"])
        self.assertEqual(code, 1)
        self.assertIn("unknown service", err)

    def test_two_port443_services_are_rejected_when_named(self):
        second = self.repo.dir / "services" / "edge2"
        second.mkdir()
        (second / "docker-compose.yml").write_text(PROXY_COMPOSE.replace("edge", "edge2"))
        code, _, err = run_cli(
            ["--root", str(self.repo.dir), "up", "edge", "edge2", "--dry-run"]
        )
        self.assertEqual(code, 1)
        self.assertIn("cannot run together", err)

    def test_unnamed_extra_proxy_is_skipped_not_fatal(self):
        second = self.repo.dir / "services" / "edge2"
        second.mkdir()
        (second / "docker-compose.yml").write_text(PROXY_COMPOSE.replace("edge", "edge2"))
        code, out, _ = run_cli(["--root", str(self.repo.dir), "up", "--dry-run"])
        self.assertEqual(code, 0)
        self.assertIn("skipping edge2", out)
        self.assertNotIn(str(second / "docker-compose.yml"), out)

    def test_urls_come_from_the_env_file(self):
        code, out, _ = run_cli(["--root", str(self.repo.dir), "urls"])
        self.assertEqual(code, 0)
        self.assertIn("https://app.example.com", out)


class DoctorTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo({"edge": PROXY_COMPOSE, "app": APP_COMPOSE})
        self.addCleanup(self.repo.cleanup)
        self.repo.add_env(
            "edge",
            {
                "PROXY_IMAGE": "traefik:v3.5",
                "EMAIL": "ops@example.com",
            },
        )
        self.repo.add_env(
            "app",
            {"APP_IMAGE": "example/app:1.2.3", "APP_TOKEN": "t", "DOMAIN": "a.example.com"},
        )
        users = self.repo.dir / "services" / "edge" / "users"
        users.write_text("admin:$apr1$abc$def\n")
        users.chmod(0o600)

    def checks(self, extra_args=()):
        code, out, _ = run_cli(
            ["--root", str(self.repo.dir), "doctor", "--json", *extra_args]
        )
        return code, {c["name"]: c for c in __import__("json").loads(out)}

    def test_resolver_mismatch_is_reported(self):
        path = self.repo.dir / "services" / "edge" / "docker-compose.yml"
        path.write_text(path.read_text().replace("resolvers.dns", "resolvers.other"))
        _, checks = self.checks()
        self.assertEqual(checks["tls resolver"]["status"], "FAIL")

    def test_matching_resolver_passes(self):
        _, checks = self.checks()
        self.assertEqual(checks["tls resolver"]["status"], "OK")

    def test_missing_env_var_is_reported(self):
        self.repo.add_env("app", {"APP_IMAGE": "example/app:1.2.3", "DOMAIN": "a.example.com"})
        _, checks = self.checks()
        self.assertEqual(checks["app env"]["status"], "FAIL")
        self.assertIn("APP_TOKEN", checks["app env"]["detail"])

    def test_world_readable_env_is_a_warning(self):
        (self.repo.dir / "services" / "app" / ".env").chmod(0o644)
        _, checks = self.checks()
        self.assertEqual(checks["app env"]["status"], "WARN")

    def test_placeholder_value_is_a_failure(self):
        self.repo.add_env(
            "app",
            {"APP_IMAGE": "example/app:1.2.3", "APP_TOKEN": "(put your token here)",
             "DOMAIN": "a.example.com"},
        )
        _, checks = self.checks()
        self.assertEqual(checks["app env"]["status"], "FAIL")

    def test_floating_tag_is_flagged(self):
        self.repo.add_env(
            "app",
            {"APP_IMAGE": "example/app:latest", "APP_TOKEN": "t", "DOMAIN": "a.example.com"},
        )
        _, checks = self.checks()
        self.assertEqual(checks["image pinning"]["status"], "WARN")
        self.assertIn("example/app:latest", checks["image pinning"]["detail"])

    def test_missing_dashboard_users_file_fails(self):
        (self.repo.dir / "services" / "edge" / "users").unlink()
        _, checks = self.checks()
        self.assertEqual(checks["dashboard auth"]["status"], "FAIL")

    def test_default_image_does_not_count_as_unpinned_by_mistake(self):
        (self.repo.dir / "services" / "app" / ".env").unlink()
        _, checks = self.checks()
        detail = checks["image pinning"]["detail"]
        self.assertNotIn("example/app:latest, example/app:latest", detail)


class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo({"edge": PROXY_COMPOSE, "app": APP_COMPOSE})
        self.addCleanup(self.repo.cleanup)
        self.repo.add_template("edge", "# token\nPROXY_IMAGE=traefik:latest\nEMAIL=\n")
        self.repo.add_template("app", "# api token\nAPP_TOKEN=\nDOMAIN=\n")

    def test_non_interactive_generates_secrets_and_600_env(self):
        code, out, err = run_cli(
            ["--root", str(self.repo.dir), "config", "--non-interactive"]
        )
        self.assertEqual(code, 0, err)
        env = homelab.read_env(self.repo.dir / "services" / "app" / ".env")
        self.assertTrue(env["APP_TOKEN"])
        self.assertEqual(
            stat.S_IMODE(
                (self.repo.dir / "services" / "app" / ".env").stat().st_mode
            ),
            0o600,
        )
        users = self.repo.dir / "services" / "edge" / "users"
        self.assertTrue(users.is_file())
        self.assertEqual(stat.S_IMODE(users.stat().st_mode), 0o600)

    def test_non_interactive_keeps_existing_values(self):
        self.repo.add_env("app", {"APP_TOKEN": "keep-me", "DOMAIN": "old.example.com"})
        run_cli(["--root", str(self.repo.dir), "config", "--non-interactive"])
        env = homelab.read_env(self.repo.dir / "services" / "app" / ".env")
        self.assertEqual(env["APP_TOKEN"], "keep-me")
        self.assertEqual(env["DOMAIN"], "old.example.com")

    def test_non_interactive_does_not_write_template_placeholders(self):
        self.repo.add_template("app", "APP_TOKEN=\nDOMAIN=(put your domain here)\n")
        self.repo.add_env("app", {})
        run_cli(["--root", str(self.repo.dir), "config", "--non-interactive"])
        env = homelab.read_env(self.repo.dir / "services" / "app" / ".env")
        self.assertEqual(env.get("DOMAIN", ""), "")


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo({"edge": PROXY_COMPOSE, "app": APP_COMPOSE})
        self.addCleanup(self.repo.cleanup)
        (self.repo.dir / "homelab.toml").write_text(
            '[snapshot]\ntool = "restic"\nrepo = "/srv/repo/restic"\n'
            'password_file = "/etc/homelab/pw"\nsource = "/srv/homelab"\n'
            'keep_daily = 3\nkeep_weekly = 2\nkeep_monthly = 1\nexclude = ["**/cache"]\n'
        )

    def test_restic_commands_are_built_correctly(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = homelab.main(["--root", str(self.repo.dir), "snapshot", "run", "--dry-run"])
        self.assertEqual(code, 0)
        text = out.getvalue()
        self.assertIn("restic --repo /srv/repo/restic --password-file /etc/homelab/pw snapshot", text)
        self.assertIn("--exclude", text)
        self.assertIn("**/cache", text)
        self.assertIn("--keep-daily 3", text)
        self.assertIn("--prune", text)
        self.assertIn("--read-data-subset=5%", text)

    def test_missing_repo_is_an_error(self):
        (self.repo.dir / "homelab.toml").write_text("[snapshot]\ntool = \"restic\"\n")
        code, _, err = run_cli(["--root", str(self.repo.dir), "snapshot", "run"])
        self.assertEqual(code, 1)
        self.assertIn("repo is not set", err)

    def test_extract_requires_a_snapshot_id(self):
        code, _, err = run_cli(["--root", str(self.repo.dir), "snapshot", "extract"])
        self.assertEqual(code, 1)
        self.assertIn("usage", err)


class HostTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo({"edge": PROXY_COMPOSE, "app": APP_COMPOSE})
        self.addCleanup(self.repo.cleanup)

    def test_host_limits_the_service_set(self):
        (self.repo.dir / "homelab.toml").write_text('[hosts.nuc]\nservices = ["app"]\n')
        code, out, _ = run_cli(
            ["--root", str(self.repo.dir), "--host", "nuc", "doctor", "--json"]
        )
        self.assertEqual(code, 1)  # no env files yet, but the failure must be about app
        names = [check["name"] for check in __import__("json").loads(out)]
        self.assertIn("app env", names)
        self.assertNotIn("edge env", names)

    def test_unknown_host_lists_what_is_configured(self):
        (self.repo.dir / "homelab.toml").write_text('[hosts.nuc]\nservices = ["app"]\n')
        code, _, err = run_cli(["--root", str(self.repo.dir), "--host", "pi", "status"])
        self.assertEqual(code, 1)
        self.assertIn("unknown host: pi", err)
        self.assertIn("nuc", err)

    def test_host_can_point_at_another_service_dir(self):
        alt = self.repo.dir / "pi" / "services" / "kuma"
        alt.mkdir(parents=True)
        (alt / "docker-compose.yml").write_text(
            'services:\n  kuma:\n    image: ${KUMA_IMAGE:-louislam/uptime-kuma:latest}\n'
            '    ports:\n      - "3001:3001"\n'
        )
        (self.repo.dir / "homelab.toml").write_text(
            '[hosts.pi]\nservices_dir = "pi/services"\nservices = ["kuma"]\n'
        )
        code, out, _ = run_cli(["--root", str(self.repo.dir), "--host", "pi", "doctor", "--json"])
        names = [check["name"] for check in __import__("json").loads(out)]
        self.assertIn("kuma env", names)
        self.assertNotIn("edge env", names)
        # a host with no proxy must not be nagged about TLS resolvers
        checks = {c["name"]: c for c in __import__("json").loads(out)}
        self.assertEqual(checks["tls resolver"]["status"], "SKIP")

    def test_host_service_typo_is_caught(self):
        (self.repo.dir / "homelab.toml").write_text('[hosts.nuc]\nservices = ["ap"]\n')
        code, _, err = run_cli(["--root", str(self.repo.dir), "--host", "nuc", "status"])
        self.assertEqual(code, 1)
        self.assertIn("unknown service(s): ap", err)


class SnapshotInitTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo({"edge": PROXY_COMPOSE})
        self.addCleanup(self.repo.cleanup)
        self.pw = self.repo.dir / "secrets"
        (self.repo.dir / "homelab.toml").write_text(
            '[snapshot]\ntool = "restic"\nrepo = "/srv/repo/restic"\n'
            f'password_file = "{self.pw}/main.pw"\nsource = "/srv/homelab"\n'
            "[[snapshot.copies]]\n"
            'name = "cold"\nrepo = "/srv/cold/restic"\n'
            f'password_file = "{self.pw}/cold.pw"\n'
        )
        self.path = os.environ["PATH"]
        self.addCleanup(lambda: os.environ.__setitem__("PATH", self.path))

    def stub_restic(self, initialised=False):
        bindir = Path(tempfile.mkdtemp(prefix="homelab-bin-"))
        self.addCleanup(shutil.rmtree, bindir, True)
        log = bindir / "restic.log"
        script = bindir / "restic"
        code = 0 if initialised else 1
        script.write_text(
            "#!/bin/sh\n"
            f'printf "%s\\n" "$*" >> "{log}"\n'
            f'case "$*" in *"cat config"*) exit {code} ;; esac\n'
            "exit 0\n"
        )
        script.chmod(0o755)
        os.environ["PATH"] = f"{bindir}:{self.path}"
        return log

    def test_init_creates_one_passphrase_per_repo(self):
        log = self.stub_restic()
        code, out, err = run_cli(["--root", str(self.repo.dir), "snapshot", "init"])
        self.assertEqual(code, 0, out + err)
        main_pw, cold_pw = self.pw / "main.pw", self.pw / "cold.pw"
        self.assertTrue(main_pw.is_file() and cold_pw.is_file())
        self.assertEqual(stat.S_IMODE(main_pw.stat().st_mode), 0o600)
        self.assertNotEqual(main_pw.read_text(), cold_pw.read_text())
        calls = log.read_text().splitlines()
        self.assertIn("--repo /srv/repo/restic", " ".join(calls))
        self.assertIn("--repo /srv/cold/restic", " ".join(calls))
        self.assertTrue([line for line in calls if line.endswith("init")])

    def test_init_leaves_an_existing_repo_and_passphrase_alone(self):
        self.pw.mkdir(parents=True)
        (self.pw / "main.pw").write_text("existing\n")
        log = self.stub_restic(initialised=True)
        code, out, _ = run_cli(["--root", str(self.repo.dir), "snapshot", "init"])
        self.assertEqual(code, 0)
        self.assertEqual((self.pw / "main.pw").read_text(), "existing\n")
        calls = log.read_text().splitlines()
        self.assertEqual([line for line in calls if line.endswith("init")], [])

    def test_dry_run_writes_nothing(self):
        code, out, _ = run_cli(["--root", str(self.repo.dir), "snapshot", "init", "--dry-run"])
        self.assertEqual(code, 0)
        self.assertIn("restic --repo /srv/repo/restic", out)
        self.assertFalse((self.pw / "main.pw").exists())

    def test_installed_timer_pins_the_config_it_was_installed_with(self):
        code, out, _ = run_cli(
            [
                "--root", str(self.repo.dir),
                "--conf", str(self.repo.dir / "homelab.toml"),
                "snapshot", "install", "--dry-run",
            ]
        )
        self.assertEqual(code, 0)
        self.assertIn(f"--conf {self.repo.dir / 'homelab.toml'}", out)
        self.assertIn("snapshot run", out)
        self.assertIn("OnCalendar=", out)


class SnapshotSourceTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo({"edge": PROXY_COMPOSE})
        self.addCleanup(self.repo.cleanup)

    def write(self, body):
        (self.repo.dir / "homelab.toml").write_text(body)

    def test_a_list_of_sources_is_snapshotted_in_one_run(self):
        self.write(
            '[snapshot]\ntool = "restic"\nrepo = "/srv/repo/restic"\n'
            'source = ["/srv/mnt/nuc/srv/homelab", "/srv/homelab"]\n'
        )
        code, out, _ = run_cli(["--root", str(self.repo.dir), "snapshot", "run", "--dry-run"])
        self.assertEqual(code, 0)
        self.assertIn("snapshot /srv/mnt/nuc/srv/homelab /srv/homelab", out)

    def test_local_hooks_run_here_even_with_remote(self):
        self.write(
            '[snapshot]\ntool = "restic"\nrepo = "/srv/repo/restic"\nsource = "/srv/homelab"\n'
            'pre = ["docker exec db true"]\npre_local = ["sqlite3 /x.db .backup /y.db"]\n'
        )
        code, out, _ = run_cli(
            ["--root", str(self.repo.dir), "snapshot", "run", "--remote", "b@nuc", "--dry-run"]
        )
        self.assertEqual(code, 0)
        self.assertIn("$ ssh b@nuc 'docker exec db true'", out)
        self.assertIn("$ bash -lc 'sqlite3 /x.db .backup /y.db'", out)

    def test_doctor_warns_about_a_dump_outside_the_snapshot(self):
        self.write(
            '[general]\ndata_dir = "/srv/homelab"\n'
            '[snapshot]\ntool = "restic"\nrepo = "/srv/repo/restic"\n'
            'source = "/srv/homelab"\npre = ["pg_dump x > /srv/dumps/x.sql"]\n'
        )
        _, out, _ = run_cli(["--root", str(self.repo.dir), "doctor", "--json"])
        checks = {c["name"]: c for c in __import__("json").loads(out)}
        self.assertEqual(checks["snapshot hooks"]["status"], "WARN")
        self.assertIn("/srv/dumps/x.sql", checks["snapshot hooks"]["detail"])

    def test_doctor_accepts_a_dump_inside_data_dir(self):
        self.write(
            '[general]\ndata_dir = "/srv/homelab"\n'
            '[snapshot]\ntool = "restic"\nrepo = "/srv/repo/restic"\n'
            'source = "/srv/mnt/nuc/srv/homelab"\n'
            'pre = ["pg_dump x > /srv/homelab/dumps/x.sql"]\n'
        )
        _, out, _ = run_cli(["--root", str(self.repo.dir), "doctor", "--json"])
        checks = {c["name"]: c for c in __import__("json").loads(out)}
        self.assertEqual(checks["snapshot hooks"]["status"], "OK")


class SecretCoverageTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo({"edge": PROXY_COMPOSE})
        self.addCleanup(self.repo.cleanup)
        self.repo.add_env("edge", {"PROXY_IMAGE": "traefik:v3.5"})

    def check(self, source):
        (self.repo.dir / "homelab.toml").write_text(
            f'[snapshot]\ntool = "restic"\nrepo = "/srv/repo/restic"\nsource = "{source}"\n'
        )
        _, out, _ = run_cli(["--root", str(self.repo.dir), "doctor", "--json"])
        return {c["name"]: c for c in __import__("json").loads(out)}["secret coverage"]

    def test_env_files_outside_the_snapshot_are_flagged(self):
        check = self.check("/srv/mnt/nuc/srv/homelab")
        self.assertEqual(check["status"], "WARN")
        self.assertIn("password manager", check["hint"])

    def test_env_files_inside_the_snapshot_are_fine(self):
        check = self.check(str(self.repo.dir))
        self.assertEqual(check["status"], "OK")


class CopyTests(unittest.TestCase):
    TOML = (
        '[snapshot]\ntool = "restic"\nrepo = "/srv/repo/restic"\n'
        'password_file = "/etc/homelab/pw"\nsource = "/srv/homelab"\n'
        "[[snapshot.copies]]\n"
        'name = "cold"\nrepo = "/srv/cold/restic"\n'
        'password_file = "/etc/homelab/cold.pw"\nkeep_daily = 14\n'
        "[[snapshot.copies]]\n"
        'name = "offsite"\nrepo = "sftp:u1@u1.your-storagebox.de:/restic"\n'
        'password_file = "/etc/homelab/off.pw"\nlimit_upload = 30000\n'
    )

    def setUp(self):
        self.repo = TempRepo({"edge": PROXY_COMPOSE})
        self.addCleanup(self.repo.cleanup)
        (self.repo.dir / "homelab.toml").write_text(self.TOML)

    def test_every_copy_target_gets_a_restic_copy(self):
        code, out, _ = run_cli(
            ["--root", str(self.repo.dir), "snapshot", "copy", "--dry-run"]
        )
        self.assertEqual(code, 0)
        self.assertIn("copy --repo2 /srv/cold/restic --password-file2 /etc/homelab/cold.pw", out)
        self.assertIn("copy --repo2 sftp:u1@u1.your-storagebox.de:/restic", out)
        self.assertIn("--limit-upload 30000", out)
        self.assertIn("forget --keep-daily 14", out)

    def test_only_limits_the_targets(self):
        code, out, _ = run_cli(
            ["--root", str(self.repo.dir), "snapshot", "copy", "--only", "cold", "--dry-run"]
        )
        self.assertEqual(code, 0)
        self.assertIn("/srv/cold/restic", out)
        self.assertNotIn("storagebox", out)

    def test_unknown_target_is_an_error(self):
        code, _, err = run_cli(
            ["--root", str(self.repo.dir), "snapshot", "copy", "--only", "nope", "--dry-run"]
        )
        self.assertEqual(code, 1)
        self.assertIn("unknown copy target: nope", err)

    def test_no_copies_configured_is_explained(self):
        (self.repo.dir / "homelab.toml").write_text('[snapshot]\nrepo = "/srv/repo/restic"\n')
        code, _, err = run_cli(["--root", str(self.repo.dir), "snapshot", "copy"])
        self.assertEqual(code, 1)
        self.assertIn("no [[snapshot.copies]]", err)

    def test_borg_copy_says_why_it_cannot(self):
        (self.repo.dir / "homelab.toml").write_text(
            self.TOML.replace('tool = "restic"', 'tool = "borg"')
        )
        code, _, err = run_cli(["--root", str(self.repo.dir), "snapshot", "copy", "--dry-run"])
        self.assertEqual(code, 1)
        self.assertIn("borg cannot copy", err)


class FakeShell:
    """Answers canned command results; records what was asked."""

    def __init__(self, answers=None):
        self.answers = answers or {}
        self.calls = []
        self.dry_run = False
        self.verbose = False

    def run(self, args, check=True, capture=True, env=None, cwd=None):
        key = " ".join(args)
        self.calls.append(key)
        code, out = self.answers.get(key, (1, ""))
        return homelab.Result(code, out, "")

    def probe(self, args):
        return self.run(args, check=False)


class ProvisionTests(unittest.TestCase):
    def stub(self, devices, answers=None):
        from types import SimpleNamespace

        conf = {"provision": {"pi": {"devices": devices, "mount": "/srv/repo"}}}
        return SimpleNamespace(
            conf=conf,
            sh=FakeShell(answers),
            args=SimpleNamespace(apply=False, yes=False),
        )

    def test_steps_cover_the_whole_chain(self):
        steps = homelab.PiProvisioner(self.stub(["/dev/a", "/dev/b"])).steps()
        cmds = [" ".join(step["cmd"]) if step.get("cmd") else "fstab" for step in steps]
        joined = " | ".join(cmds)
        for expected in (
            "mdadm --create /dev/md/repo --level=1 --raid-devices=2 /dev/a /dev/b",
            "vgcreate vg_repo /dev/md/repo",
            "lvcreate -l 100%FREE -n lv_repo vg_repo",
            "mkfs.ext4 -m 1 -L repo /dev/vg_repo/lv_repo",
            "mkdir -p /srv/repo",
            "mount /dev/vg_repo/lv_repo /srv/repo",
        ):
            self.assertIn(expected, joined)

    def test_mount_is_persisted_before_it_is_mounted(self):
        steps = homelab.PiProvisioner(self.stub(["/dev/a", "/dev/b"])).steps()
        kinds = ["fstab" if step.get("fn") else step["cmd"][0] for step in steps]
        self.assertLess(kinds.index("fstab"), kinds.index("mount"))

    def test_two_devices_are_required(self):
        with self.assertRaises(homelab.HomelabError):
            homelab.PiProvisioner(self.stub(["/dev/only-one"])).run()

    def test_clean_devices_pass(self):
        answers = {
            "findmnt -no SOURCE /": (0, "/dev/mmcblk0p2\n"),
            "test -b /dev/sda": (0, ""),
            "lsblk -no MOUNTPOINT /dev/sda": (0, ""),
            "blkid -p -o value -s TYPE /dev/sda": (0, ""),
        }
        self.assertEqual(
            homelab.validate_pi_devices(["/dev/sda"], FakeShell(answers)), []
        )

    def test_mounted_device_is_refused(self):
        answers = {
            "findmnt -no SOURCE /": (0, "/dev/mmcblk0p2\n"),
            "test -b /dev/sda": (0, ""),
            "lsblk -no MOUNTPOINT /dev/sda": (0, "/mnt/data\n"),
            "blkid -p -o value -s TYPE /dev/sda": (0, ""),
        }
        problems = homelab.validate_pi_devices(["/dev/sda"], FakeShell(answers))
        self.assertTrue(any("mounted at /mnt/data" in p for p in problems))

    def test_device_with_a_signature_is_refused(self):
        answers = {
            "findmnt -no SOURCE /": (0, "/dev/mmcblk0p2\n"),
            "test -b /dev/sda": (0, ""),
            "lsblk -no MOUNTPOINT /dev/sda": (0, ""),
            "blkid -p -o value -s TYPE /dev/sda": (0, "ext4\n"),
        }
        problems = homelab.validate_pi_devices(["/dev/sda"], FakeShell(answers))
        self.assertTrue(any("wipefs -a /dev/sda" in p for p in problems))

    def test_root_device_is_refused(self):
        answers = {
            "findmnt -no SOURCE /": (0, "/dev/sda\n"),
            "test -b /dev/sda": (0, ""),
            "lsblk -no MOUNTPOINT /dev/sda": (0, ""),
            "blkid -p -o value -s TYPE /dev/sda": (0, ""),
        }
        problems = homelab.validate_pi_devices(["/dev/sda"], FakeShell(answers))
        self.assertTrue(any("root filesystem" in p for p in problems))

    def test_non_block_device_is_refused(self):
        answers = {"findmnt -no SOURCE /": (0, "/dev/mmcblk0p2\n")}
        problems = homelab.validate_pi_devices(["/dev/nope"], FakeShell(answers))
        self.assertTrue(any("not a block device" in p for p in problems))


class ProvisionCliTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo({"edge": PROXY_COMPOSE})
        self.addCleanup(self.repo.cleanup)

    def test_dry_run_refuses_devices_that_are_not_block_devices(self):
        (self.repo.dir / "homelab.toml").write_text(
            '[provision.pi]\ndevices = ["/dev/not-a-disk-1", "/dev/not-a-disk-2"]\n'
        )
        code, out, _ = run_cli(
            ["--root", str(self.repo.dir), "provision", "pi", "--dry-run"]
        )
        self.assertEqual(code, 1)
        self.assertIn("not a block device", out)
        self.assertIn("mdadm --create", out)

    def test_missing_devices_points_at_the_config(self):
        code, _, err = run_cli(["--root", str(self.repo.dir), "provision", "pi", "--dry-run"])
        self.assertEqual(code, 1)
        self.assertIn("[provision.pi] devices", err)


class ProfileTests(unittest.TestCase):
    PROFILED = """services:
  vpn:
    image: ${VPN_IMAGE:-tailscale/tailscale:latest}
    profiles: ["vpn"]
    network_mode: host
"""

    def setUp(self):
        self.repo = TempRepo({"app": APP_COMPOSE, "vpn": self.PROFILED})
        self.addCleanup(self.repo.cleanup)

    def test_profiled_service_is_skipped_by_default(self):
        code, out, _ = run_cli(["--root", str(self.repo.dir), "up", "--dry-run"])
        self.assertEqual(code, 0)
        self.assertIn("skipping vpn", out)
        self.assertNotIn("services/vpn/docker-compose.yml up", out)

    def test_profile_flag_starts_it(self):
        code, out, _ = run_cli(
            ["--root", str(self.repo.dir), "up", "--profile", "vpn", "--dry-run"]
        )
        self.assertEqual(code, 0)
        self.assertNotIn("skipping vpn", out)
        self.assertIn("--profile vpn up -d", out)

    def test_service_profiles_reads_both_forms(self):
        inline = self.repo.dir / "services" / "vpn" / "docker-compose.yml"
        self.assertEqual(homelab.service_profiles(inline.parent), ["vpn"])
        block = self.repo.dir / "services" / "app" / "docker-compose.yml"
        block.write_text("services:\n  app:\n    image: x\n    profiles:\n      - a\n      - b\n")
        self.assertEqual(homelab.service_profiles(block.parent), ["a", "b"])


class MigrateTests(unittest.TestCase):
    COMPOSE = """services:
  app:
    image: ${APP_IMAGE:-example/app:latest}
    volumes:
      - ${DATA_DIR:-.}/data:/var/lib/app
      - /var/run/docker.sock:/var/run/docker.sock
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "8080:80"
"""

    def setUp(self):
        self.repo = TempRepo({"app": self.COMPOSE})
        self.addCleanup(self.repo.cleanup)
        self.target = Path(tempfile.mkdtemp(prefix="homelab-srv-"))
        self.addCleanup(shutil.rmtree, self.target, True)
        self.path = os.environ["PATH"]
        self.addCleanup(lambda: os.environ.__setitem__("PATH", self.path))
        self.src = self.repo.dir / "services" / "app" / "data"

    def stub_rsync(self, verify_output=""):
        """A stand-in rsync: copies on a real run, prints on --dry-run."""
        bindir = Path(tempfile.mkdtemp(prefix="homelab-bin-"))
        self.addCleanup(shutil.rmtree, bindir, True)
        script = bindir / "rsync"
        script.write_text(
            "#!/bin/sh\n"
            'for a in "$@"; do\n'
            f'  if [ "$a" = "--dry-run" ]; then echo "{verify_output}"; exit 0; fi\n'
            "done\n"
            'src=""; dst=""\n'
            'for a in "$@"; do src="$dst"; dst="$a"; done\n'
            'cp -a "${src}." "$dst"\n'
        )
        script.chmod(0o755)
        os.environ["PATH"] = f"{bindir}:{self.path}"

    def recording_rsync(self):
        """A stand-in rsync that records its argv and succeeds."""
        bindir = Path(tempfile.mkdtemp(prefix="homelab-bin-"))
        self.addCleanup(shutil.rmtree, bindir, True)
        log = bindir / "calls.log"
        script = bindir / "rsync"
        script.write_text(
            "#!/bin/sh\n"
            f'printf "%s\\n" "$*" >> "{log}"\n'
            "exit 0\n"
        )
        script.chmod(0o755)
        os.environ["PATH"] = f"{bindir}:{self.path}"
        return log

    def seed(self):
        self.src.mkdir(parents=True)
        (self.src / "x.txt").write_text("hi")

    def test_interpolate_prefers_env_then_default(self):
        self.assertEqual(homelab.interpolate("${A:-x}", {}), "x")
        self.assertEqual(homelab.interpolate("${A:-x}", {"A": "y"}), "y")
        self.assertEqual(homelab.interpolate("${A:-x}", {"A": ""}), "x")
        self.assertEqual(homelab.interpolate("${A}", {"A": "z"}), "z")

    def test_bind_sources_skips_socket_host_config_and_ports(self):
        svc = self.repo.dir / "services" / "app"
        found = homelab.bind_sources(svc, {})
        self.assertEqual([path.name for path, _ in found], ["data"])
        self.assertEqual(found[0][1], "/var/lib/app")

    def test_missing_destination_is_an_error(self):
        code, out, err = run_cli(["--root", str(self.repo.dir), "migrate", "data"])
        self.assertEqual(code, 1)
        self.assertIn("no destination", err)

    def test_files_are_not_migrated(self):
        compose = self.repo.dir / "services" / "app" / "docker-compose.yml"
        compose.write_text(self.COMPOSE.replace('"8080:80"', "./acme.json:/acme.json"))
        (self.repo.dir / "services" / "app" / "acme.json").write_text("{}")
        code, out, _ = run_cli(
            ["--root", str(self.repo.dir), "migrate", "data", "--to", str(self.target)]
        )
        self.assertEqual(code, 0)
        self.assertIn("nothing to move", out)

    def test_plan_lists_the_move_and_copies_nothing(self):
        self.seed()
        code, out, _ = run_cli(
            ["--root", str(self.repo.dir), "migrate", "data", "--to", str(self.target)]
        )
        self.assertEqual(code, 0)
        self.assertIn("this was a plan", out)
        self.assertIn(str(self.target / "app" / "data"), out)
        self.assertFalse((self.target / "app" / "data").exists())

    def test_apply_copies_verifies_and_records_data_dir(self):
        self.seed()
        self.stub_rsync()
        code, out, err = run_cli(
            [
                "--root", str(self.repo.dir),
                "migrate", "data", "--to", str(self.target),
                "--apply",
            ]
        )
        self.assertEqual(code, 0, out + err)
        self.assertEqual((self.target / "app" / "data" / "x.txt").read_text(), "hi")
        self.assertIn("verified", out)
        env = homelab.read_env(self.repo.dir / "services" / "app" / ".env")
        self.assertEqual(env["DATA_DIR"], str(self.target / "app"))

    def test_apply_refuses_a_copy_that_does_not_match(self):
        self.seed()
        self.stub_rsync(verify_output=">f.stage x.txt")
        code, out, err = run_cli(
            ["--root", str(self.repo.dir), "migrate", "data", "--to", str(self.target), "--apply"]
        )
        self.assertEqual(code, 1)
        self.assertIn("does not match", err)

    def test_from_remote_copies_from_the_remote_checkout(self):
        log = self.recording_rsync()
        code, out, err = run_cli(
            [
                "--root", str(self.repo.dir), "migrate", "data",
                "--from", "pi.lan:/opt/homelab", "--to", str(self.target), "--apply",
            ]
        )
        self.assertEqual(code, 0, out + err)
        calls = log.read_text().splitlines()
        copy = [call for call in calls if "--dry-run" not in call]
        self.assertEqual(len(copy), 1, calls)
        self.assertIn("pi.lan:/opt/homelab/services/app/data/", copy[0])
        self.assertIn("--numeric-ids", copy[0])

    def test_from_plan_shows_the_remote_path(self):
        code, out, _ = run_cli(
            [
                "--root", str(self.repo.dir), "migrate", "data",
                "--from", "pi.lan:/opt/homelab", "--to", str(self.target),
            ]
        )
        self.assertEqual(code, 0)
        self.assertIn("pi.lan:/opt/homelab/services/app/data", out)
        self.assertIn("this was a plan", out)

    def test_from_needs_a_remote_root(self):
        code, out, err = run_cli(
            ["--root", str(self.repo.dir), "migrate", "data", "--from", "pi.lan",
             "--to", str(self.target)]
        )
        self.assertEqual(code, 1)
        self.assertIn("HOST:/path/to/checkout", err)

    def test_state_already_under_the_target_is_left_alone(self):
        self.repo.add_env("app", {"DATA_DIR": str(self.target / "app")})
        (self.target / "app" / "data").mkdir(parents=True)
        code, out, _ = run_cli(
            ["--root", str(self.repo.dir), "migrate", "data", "--to", str(self.target)]
        )
        self.assertEqual(code, 0)
        self.assertIn("already under", out)
        self.assertIn("nothing to move", out)


class VolumeTests(unittest.TestCase):
    NAMED = """services:
  app:
    image: ${APP_IMAGE:-example/app:latest}
    volumes:
      - dbdata:/var/lib/mysql
    command:
      - "--entrypoints.web.address=:80"
      - "--no-new-privileges"
    ports:
      - "8080:80"
"""

    BOUND = """x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"

services:
  app:
    image: ${APP_IMAGE:-example/app:latest}
    logging: *default-logging
    volumes:
      - ${DATA_DIR:-.}/data:/var/lib/app
"""

    def test_named_volume_is_not_a_bind_mount(self):
        repo = TempRepo({"app": self.NAMED})
        self.addCleanup(repo.cleanup)
        svc = repo.dir / "services" / "app"
        self.assertEqual(homelab.named_volumes(svc, {}), ["dbdata"])
        self.assertEqual(homelab.bind_sources(svc, {}), [])

    def test_command_flags_are_not_mistaken_for_volumes(self):
        repo = TempRepo({"app": self.NAMED})
        self.addCleanup(repo.cleanup)
        svc = repo.dir / "services" / "app"
        self.assertNotIn("--no-new-privileges", homelab.named_volumes(svc, {}))
        self.assertNotIn("--entrypoints.web.address=", homelab.named_volumes(svc, {}))

    def test_doctor_flags_state_in_docker_root(self):
        repo = TempRepo({"app": self.NAMED})
        self.addCleanup(repo.cleanup)
        _, out, _ = run_cli(["--root", str(repo.dir), "doctor", "--json"])
        checks = {c["name"]: c for c in __import__("json").loads(out)}
        self.assertEqual(checks["named volumes"]["status"], "WARN")
        self.assertIn("dbdata", checks["named volumes"]["detail"])

    def test_doctor_passes_with_bind_mounts_and_capped_logs(self):
        repo = TempRepo({"app": self.BOUND})
        self.addCleanup(repo.cleanup)
        _, out, _ = run_cli(["--root", str(repo.dir), "doctor", "--json"])
        checks = {c["name"]: c for c in __import__("json").loads(out)}
        self.assertEqual(checks["named volumes"]["status"], "OK")
        self.assertEqual(checks["log limits"]["status"], "OK")


class AcmeStorageTests(unittest.TestCase):
    COMPOSE = """services:
  edge:
    image: ${PROXY_IMAGE:-traefik:latest}
    ports:
      - "443:443"
    labels:
      - "traefik.http.routers.dash.tls.certresolver=dns"
    command:
      - "--certificatesresolvers.dns.acme.dnschallenge=true"
      - "--certificatesresolvers.dns.acme.dnschallenge.provider=ipv64"
      - "--certificatesresolvers.dns.acme.storage=/letsencrypt/acme.json"
    environment:
      - IPV64_API_KEY=${IPV64_API_KEY}
    volumes:
      - ./letsencrypt:/letsencrypt
"""

    def setUp(self):
        self.repo = TempRepo({"edge": self.COMPOSE})
        self.addCleanup(self.repo.cleanup)
        self.repo.add_env("edge", {"PROXY_IMAGE": "traefik:v3.5", "IPV64_API_KEY": "k"})
        self.acme = self.repo.dir / "services" / "edge" / "letsencrypt" / "acme.json"

    def checks(self):
        _, out, _ = run_cli(["--root", str(self.repo.dir), "doctor", "--json"])
        return {c["name"]: c for c in __import__("json").loads(out)}

    def write(self, mode):
        self.acme.parent.mkdir(parents=True, exist_ok=True)
        self.acme.write_text("{}")
        self.acme.chmod(mode)

    def test_world_readable_acme_json_is_a_failure(self):
        self.write(0o644)
        self.assertEqual(self.checks()["acme storage"]["status"], "FAIL")

    def test_600_acme_json_passes(self):
        self.write(0o600)
        self.assertEqual(self.checks()["acme storage"]["status"], "OK")

    def test_missing_acme_json_is_a_warning(self):
        check = self.checks()["acme storage"]
        self.assertEqual(check["status"], "WARN")
        self.assertIn("install -m 600", check["hint"])


class MigrateScopeTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo(
            {
                "app": MigrateTests.COMPOSE,
                "edge": PROXY_COMPOSE.replace(
                    "image: ${PROXY_IMAGE:-traefik:latest}",
                    "image: ${PROXY_IMAGE:-traefik:latest}\n    volumes:\n      - ./letsencrypt:/letsencrypt",
                ),
            }
        )
        self.addCleanup(self.repo.cleanup)
        self.target = Path(tempfile.mkdtemp(prefix="homelab-srv-"))
        self.addCleanup(shutil.rmtree, self.target, True)

    def test_a_service_without_data_dir_is_left_alone(self):
        (self.repo.dir / "services" / "edge" / "letsencrypt").mkdir()
        code, out, _ = run_cli(
            ["--root", str(self.repo.dir), "migrate", "data", "--to", str(self.target)]
        )
        self.assertEqual(code, 0)
        self.assertIn("leaving edge alone", out)
        self.assertNotIn("letsencrypt", out.split("nothing to move")[0])


class RealRepoTests(unittest.TestCase):

    def test_every_compose_file_parses(self):
        if not shutil.which("docker"):
            self.skipTest("docker not installed")
        for path in sorted((REPO / "services").glob("*/docker-compose.yml")):
            result = subprocess.run(
                ["docker", "compose", "-f", str(path), "config"],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, f"{path}: {result.stderr}")

    def test_resolver_labels_match_the_proxy(self):
        code, out, _ = run_cli(["--root", str(REPO), "doctor", "--json"])
        checks = {c["name"]: c for c in __import__("json").loads(out)}
        self.assertEqual(checks["tls resolver"]["status"], "OK", checks["tls resolver"])

    def test_cli_has_no_third_party_imports(self):
        source = CLI.read_text()
        for module in ("import yaml", "import requests", "import toml\n", "import dotenv"):
            self.assertNotIn(module, source)
        self.assertTrue(source.startswith("#!/usr/bin/env python3"))


if __name__ == "__main__":
    unittest.main()
