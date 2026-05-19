// First-run bypass — simulate Firefox has already been executed
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("browser.laterrun.enabled", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);

// Quit without confirmation
user_pref("browser.warnOnQuit", false);
user_pref("browser.sessionstore.warnOnQuit", false);

// Pin uBlock Origin and Adblock Plus to the toolbar
user_pref("browser.uiCustomization.state", "{\"placements\":{\"widget-overflow-fixed-list\":[],\"unified-extensions-area\":[],\"nav-bar\":[\"back-button\",\"forward-button\",\"stop-reload-button\",\"home-button\",\"urlbar-container\",\"downloads-button\",\"ublock0_raymondhill_net-browser-action\",\"_d10d0bf8-f5b5-c8b4-a8b2-2b9879e08c5d_-browser-action\",\"fxa-toolbar-menu-button\"],\"toolbar-menubar\":[\"menubar-items\"],\"TabsToolbar\":[\"firefox-view-button\",\"tabbrowser-tabs\",\"new-tab-button\",\"alltabs-button\"],\"PersonalToolbar\":[\"personal-bookmarks\"]},\"seen\":[\"save-to-pocket-button\",\"developer-button\",\"ublock0_raymondhill_net-browser-action\",\"_d10d0bf8-f5b5-c8b4-a8b2-2b9879e08c5d_-browser-action\"],\"dirtyAreaCache\":[\"nav-bar\",\"unified-extensions-area\"],\"currentVersion\":20,\"newElementCount\":2}");
