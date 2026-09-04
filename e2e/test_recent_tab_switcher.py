"""Recent Tab switcher state and commit behavior in the real Debug app."""

from _harness import notify, wait_for


def _status(app):
    return app.cli_json("status")["status"]


def _active_tab_id(app):
    return next(tab["id"] for tab in app.cli_json("tab", "list")["tabs"] if tab["active"])


def _switcher_has_selection(app, tab_id):
    status = _status(app)
    return status if status["recentTabSwitcherVisible"] and status["recentTabSelectedTabID"] == tab_id else None


def _switcher_is_hidden(app):
    status = _status(app)
    return status if not status["recentTabSwitcherVisible"] else None


def test_recent_tab_switcher_state_machine_in_debug_app(app, fresh_tab):
    original_id = fresh_tab["id"]
    app.cli("tab", "rename", original_id, "Original A")
    recent_id = app.cli_json("tab", "new")["tabs"][0]["id"]
    app.cli("tab", "rename", recent_id, "Recent B")
    current_id = app.cli_json("tab", "new")["tabs"][0]["id"]
    app.cli("tab", "rename", current_id, "Current C")

    # First press highlights the previous MRU tab without replacing the live
    # terminal underneath the overlay.
    notify("recent-tab-cycle")
    wait_for(
        lambda: _switcher_has_selection(app, recent_id),
        message="the Recent Tab switcher to highlight the previous tab",
    )
    assert _active_tab_id(app) == current_id

    # Advancing changes only the highlight. Cancel leaves the original
    # terminal active.
    notify("recent-tab-cycle")
    wait_for(
        lambda: _switcher_has_selection(app, original_id),
        message="the Recent Tab highlight to advance in MRU order",
    )
    assert _active_tab_id(app) == current_id

    notify("recent-tab-cancel")
    wait_for(
        lambda: _switcher_is_hidden(app),
        message="the Recent Tab switcher to cancel",
    )
    assert _active_tab_id(app) == current_id

    # A fresh cycle still starts from the same MRU order; committing selects
    # exactly the highlighted tab.
    notify("recent-tab-cycle")
    wait_for(
        lambda: _switcher_has_selection(app, recent_id),
        message="a fresh Recent Tab cycle",
    )
    notify("recent-tab-commit")
    wait_for(
        lambda: _active_tab_id(app) == recent_id,
        message="Recent Tab release to commit the highlighted tab",
    )
    assert not _status(app)["recentTabSwitcherVisible"]
