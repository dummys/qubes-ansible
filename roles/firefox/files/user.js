// First-run bypass — simulate Firefox has already been executed
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("browser.laterrun.enabled", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);

// Quit without confirmation
user_pref("browser.warnOnQuit", false);
user_pref("browser.sessionstore.warnOnQuit", false);
