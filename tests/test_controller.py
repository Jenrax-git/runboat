import datetime
from unittest.mock import AsyncMock, patch

import pytest

from runboat.constants import SOURCE_DB_USE_LAST
from runboat.controller import Controller
from runboat.exceptions import NoPreviousBuildError
from runboat.github import CommitInfo
from runboat.models import Build, BuildInitStatus, BuildStatus


def _make_build(
    name: str,
    *,
    repo: str = "oca/mis-builder",
    target_branch: str = "16.0",
    pr: int | None = None,
    git_commit: str = "abc123",
    status: BuildStatus = BuildStatus.started,
    created: datetime.datetime | None = None,
) -> Build:
    return Build(
        name=name,
        deployment_name=name + "-odoo",
        commit_info=CommitInfo(
            repo=repo,
            target_branch=target_branch,
            pr=pr,
            git_commit=git_commit,
            topics=[],
        ),
        status=status,
        init_status=BuildInitStatus.succeeded,
        desired_replicas=1,
        last_scaled=datetime.datetime(2024, 1, 1, 12, 0, 0),
        created=created or datetime.datetime(2024, 1, 1, 11, 0, 0),
    )


def _make_commit_info(
    *,
    repo: str = "oca/mis-builder",
    target_branch: str = "16.0",
    pr: int | None = None,
    git_commit: str = "abc123",
) -> CommitInfo:
    return CommitInfo(
        repo=repo,
        target_branch=target_branch,
        pr=pr,
        git_commit=git_commit,
        topics=[],
    )


# ---------------------------------------------------------------------------
# _resolve_copy_db_from
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_resolve_copy_db_from_explicit_name() -> None:
    """An explicit build name is returned as-is, no DB search."""
    ctrl = Controller()
    result = await ctrl._resolve_copy_db_from(
        _make_commit_info(), source_db="b-explicit", source_db_required=True
    )
    assert result == "b-explicit"


@pytest.mark.asyncio
async def test_resolve_copy_db_from_last_returns_most_recent() -> None:
    """SOURCE_DB_USE_LAST returns the most recent non-undeploying build."""
    ctrl = Controller()
    old_build = _make_build("b-old", git_commit="sha1")
    recent_build = _make_build(
        "b-recent",
        git_commit="sha2",
        created=datetime.datetime(2024, 2, 1, 12, 0, 0),
    )
    ctrl.db.add(old_build)
    ctrl.db.add(recent_build)

    result = await ctrl._resolve_copy_db_from(
        _make_commit_info(), source_db=SOURCE_DB_USE_LAST, source_db_required=True
    )
    assert result == "b-recent"


@pytest.mark.asyncio
async def test_resolve_copy_db_from_last_excludes_undeploying() -> None:
    """Undeploying builds are excluded because their DB may already be dropped."""
    ctrl = Controller()
    ctrl.db.add(_make_build("b-old", git_commit="sha1"))
    ctrl.db.add(
        _make_build(
            "b-undeploying",
            git_commit="sha2",
            status=BuildStatus.undeploying,
            created=datetime.datetime(2024, 2, 1, 12, 0, 0),
        )
    )

    result = await ctrl._resolve_copy_db_from(
        _make_commit_info(), source_db=SOURCE_DB_USE_LAST, source_db_required=True
    )
    assert result == "b-old"


@pytest.mark.asyncio
async def test_resolve_copy_db_from_last_excludes_self() -> None:
    """The excluded build (self) is skipped to avoid a self-referencing copy."""
    ctrl = Controller()
    ctrl.db.add(_make_build("b-prev", git_commit="sha1"))
    ctrl.db.add(
        _make_build(
            "b-current",
            git_commit="sha2",
            created=datetime.datetime(2024, 2, 1, 12, 0, 0),
        )
    )

    # Exclude b-current (the existing build being redeployed).
    result = await ctrl._resolve_copy_db_from(
        _make_commit_info(),
        source_db=SOURCE_DB_USE_LAST,
        source_db_required=True,
        exclude_build_name="b-current",
    )
    assert result == "b-prev"


@pytest.mark.asyncio
async def test_resolve_copy_db_from_last_no_builds_required_raises() -> None:
    """Raises NoPreviousBuildError when required and no eligible builds exist."""
    ctrl = Controller()

    with pytest.raises(NoPreviousBuildError):
        await ctrl._resolve_copy_db_from(
            _make_commit_info(), source_db=SOURCE_DB_USE_LAST, source_db_required=True
        )


@pytest.mark.asyncio
async def test_resolve_copy_db_from_last_no_builds_not_required_returns_none() -> None:
    """Returns None (no warning is an error) when not required and no builds exist."""
    ctrl = Controller()

    result = await ctrl._resolve_copy_db_from(
        _make_commit_info(), source_db=SOURCE_DB_USE_LAST, source_db_required=False
    )
    assert result is None


@pytest.mark.asyncio
async def test_resolve_copy_db_from_last_pr() -> None:
    """SOURCE_DB_USE_LAST searches by pr when commit_info has a pr."""
    ctrl = Controller()
    # Build for the same PR
    ctrl.db.add(_make_build("b-pr", git_commit="sha1", pr=42))
    # Build for the branch (no pr) — should NOT be returned
    ctrl.db.add(_make_build("b-branch", git_commit="sha2"))

    result = await ctrl._resolve_copy_db_from(
        _make_commit_info(pr=42),
        source_db=SOURCE_DB_USE_LAST,
        source_db_required=True,
    )
    assert result == "b-pr"


# ---------------------------------------------------------------------------
# deploy_commit
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_deploy_commit_new_build_no_source_db() -> None:
    """New build without source_db calls Build.deploy with no copy_db_from."""
    ctrl = Controller()
    commit_info = _make_commit_info()

    with patch("runboat.controller.Build.deploy", new_callable=AsyncMock) as mock_deploy:
        await ctrl.deploy_commit(commit_info)
        mock_deploy.assert_awaited_once_with(commit_info, copy_db_from=None)


@pytest.mark.asyncio
async def test_deploy_commit_new_build_with_source_db() -> None:
    """New build with explicit source_db calls Build.deploy with copy_db_from set."""
    ctrl = Controller()
    commit_info = _make_commit_info()
    ctrl.db.add(_make_build("b-source", git_commit="other"))

    with patch("runboat.controller.Build.deploy", new_callable=AsyncMock) as mock_deploy:
        await ctrl.deploy_commit(commit_info, source_db="b-source")
        mock_deploy.assert_awaited_once_with(commit_info, copy_db_from="b-source")


@pytest.mark.asyncio
async def test_deploy_commit_existing_build_no_source_db_does_nothing() -> None:
    """Existing build without source_db is silently ignored (original behavior)."""
    ctrl = Controller()
    commit_info = _make_commit_info()
    ctrl.db.add(_make_build("b-existing"))

    with (
        patch("runboat.controller.Build.deploy", new_callable=AsyncMock) as mock_deploy,
        patch.object(Build, "redeploy", new_callable=AsyncMock) as mock_redeploy,
    ):
        await ctrl.deploy_commit(commit_info)
        mock_deploy.assert_not_awaited()
        mock_redeploy.assert_not_awaited()


@pytest.mark.asyncio
async def test_deploy_commit_existing_build_with_explicit_source_db_redeploys() -> None:
    """Existing build + explicit source_db → redeploy with the specified copy_db_from."""
    ctrl = Controller()
    commit_info = _make_commit_info()
    existing = _make_build("b-existing")
    ctrl.db.add(existing)

    with patch.object(Build, "redeploy", new_callable=AsyncMock) as mock_redeploy:
        await ctrl.deploy_commit(commit_info, source_db="b-other-source")
        mock_redeploy.assert_awaited_once_with(copy_db_from="b-other-source")


@pytest.mark.asyncio
async def test_deploy_commit_existing_build_with_source_db_last_redeploys() -> None:
    """Existing build + source_db=last → redeploy with the previous build as source."""
    ctrl = Controller()
    commit_info = _make_commit_info(git_commit="sha-current")
    previous = _make_build("b-previous", git_commit="sha-prev")
    existing = _make_build(
        "b-existing",
        git_commit="sha-current",
        created=datetime.datetime(2024, 2, 1, 12, 0, 0),
    )
    ctrl.db.add(previous)
    ctrl.db.add(existing)

    with patch.object(Build, "redeploy", new_callable=AsyncMock) as mock_redeploy:
        await ctrl.deploy_commit(
            commit_info, source_db=SOURCE_DB_USE_LAST, source_db_required=False
        )
        # Must use b-previous, not b-existing (self-reference excluded)
        mock_redeploy.assert_awaited_once_with(copy_db_from="b-previous")


@pytest.mark.asyncio
async def test_deploy_commit_existing_build_source_db_last_no_other_build() -> None:
    """Existing build + source_db=last + no other builds → redeploy with copy_db_from=None."""
    ctrl = Controller()
    commit_info = _make_commit_info()
    ctrl.db.add(_make_build("b-existing"))

    with patch.object(Build, "redeploy", new_callable=AsyncMock) as mock_redeploy:
        await ctrl.deploy_commit(
            commit_info, source_db=SOURCE_DB_USE_LAST, source_db_required=False
        )
        mock_redeploy.assert_awaited_once_with(copy_db_from=None)


# ---------------------------------------------------------------------------
# Build.redeploy with copy_db_from
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_build_redeploy_uses_provided_copy_db_from() -> None:
    """redeploy(copy_db_from=X) passes X to _deploy, ignoring self.copy_db_from."""
    build = _make_build("b-existing")

    with (
        patch("runboat.models.k8s.kill_job", new_callable=AsyncMock),
        patch.object(Build, "_deploy", new_callable=AsyncMock) as mock_deploy,
        patch("runboat.models.github.notify_status", new_callable=AsyncMock),
    ):
        await build.redeploy(copy_db_from="b-new-source")
        _, kwargs = mock_deploy.call_args
        assert kwargs.get("copy_db_from") == "b-new-source"


@pytest.mark.asyncio
async def test_build_redeploy_falls_back_to_self_copy_db_from() -> None:
    """redeploy() without argument preserves self.copy_db_from."""
    build = _make_build("b-existing")
    build = build.model_copy(update={"copy_db_from": "b-original-source"})

    with (
        patch("runboat.models.k8s.kill_job", new_callable=AsyncMock),
        patch.object(Build, "_deploy", new_callable=AsyncMock) as mock_deploy,
        patch("runboat.models.github.notify_status", new_callable=AsyncMock),
    ):
        await build.redeploy()
        _, kwargs = mock_deploy.call_args
        assert kwargs.get("copy_db_from") == "b-original-source"
