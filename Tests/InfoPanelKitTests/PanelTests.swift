import Testing

/// The panel's suites (each in an extension), one test at a time across all of them: the press tests run nested run
/// loops (`Clicks.click`), in which another suite's main-actor work would run too, and a run loop stop that work
/// leaves behind could end the main run, so the process quit mid-run as if every test had passed.
@Suite(.serialized) enum PanelTests {}
