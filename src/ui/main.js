Ext.namespace("SYNO.SDS.CPUTemp");

// -----------------------------------------------------------------
// App entry point
// -----------------------------------------------------------------
Ext.define("SYNO.SDS._ThirdParty.App.CPUTemp", {
    extend: "SYNO.SDS.AppInstance",
    appWindowName: "SYNO.SDS.CPUTemp.MainWindow",
    constructor: function() {
        this.callParent(arguments);
    }
});

// -----------------------------------------------------------------
// Shared API helper
// -----------------------------------------------------------------
SYNO.SDS.CPUTemp.API_PATH = "/webman/3rdparty/CPUTemp/api.cgi";

SYNO.SDS.CPUTemp.apiCall = function(action, params, callback) {
    Ext.Ajax.request({
        url: SYNO.SDS.CPUTemp.API_PATH,
        method: "GET",
        params: Ext.apply({ action: action, _ts: new Date().getTime() }, params || {}),
        success: function(response) {
            var resp;
            try {
                resp = Ext.decode(response.responseText);
            } catch (e) {
                resp = { success: false, message: "Bad response from api.cgi" };
            }
            callback(resp);
        },
        failure: function() {
            callback({ success: false, message: "Request to api.cgi failed" });
        }
    });
};

// -----------------------------------------------------------------
// Main window - runs the script, shows the log, and hosts the
// Settings dialog as an in-window modal (not a second AppWindow -
// see NOTES.md for why).
// -----------------------------------------------------------------
Ext.define("SYNO.SDS.CPUTemp.MainWindow", {
    extend: "SYNO.SDS.AppWindow",

    constructor: function(a) {
        this.appInstance = a.appInstance;
        SYNO.SDS.CPUTemp.MainWindow.superclass.constructor.call(this, Ext.apply({
            layout: "fit",
            resizable: true,
            cls: "syno-app-win cputemp-win",
            maximizable: true,
            minimizable: true,
            showHelp: false,
            width: 640,
            height: 480,
            html: this.buildHtml(),
            listeners: {
                afterrender: {
                    fn: this.onAfterRender,
                    scope: this
                }
            }
        }, a));
    },

    buildHtml: function() {
        return [
            '<style>',
            '  .cputemp-log { -webkit-user-select: text; -moz-user-select: text; -ms-user-select: text; user-select: text; }',
            '  .cputemp-body { display:flex; flex-direction:column; height:100%; padding:8px; box-sizing:border-box; position:relative; }',
            '  .cputemp-toolbar { flex:0 0 auto; padding-bottom:8px; display:flex; align-items:center; gap:8px; }',
            '  .cputemp-toolbar button { padding:5px 18px; cursor:pointer; border-radius:4px; font-size:13px; font-weight:bold; border:1px solid #ccc; background-color:#fff; color:#555; }',
            '  .cputemp-toolbar button:hover { border:1px solid #aaa; background-color:#f0f0f0; }',
            '  .cputemp-status { font-size:13px; color:#888; }',
            '  .cputemp-log { flex:1 1 auto; margin:0; overflow:auto; background:#161eb5; color:#ddd; padding:8px; font-family:Verdana,Arial,sans-serif; font-size:12px; white-space:pre-wrap; border-radius:4px; }',
            '  .cputemp-modal-backdrop { display:none; position:absolute; top:0; left:0; right:0; bottom:0; background:rgba(0,0,0,0.45); z-index:1000; align-items:center; justify-content:center; }',
            '  .cputemp-modal-backdrop.open { display:flex; }',
            '  .cputemp-modal { position:relative; background:#fff; color:#222; width:340px; padding:20px; border-radius:6px; box-shadow:0 4px 24px rgba(0,0,0,0.35); }',
            '  .cputemp-modal-close { position:absolute; top:8px; right:10px; border:none; background:none; font-size:16px; cursor:pointer; color:#666; line-height:1; padding:4px; }',
            '  .cputemp-modal-close:hover { color:#000; }',
            '  .cputemp-row { margin-bottom:14px; }',
            '  .cputemp-row label { display:inline-block; margin-bottom:4px; }',
            '  .cputemp-settings-buttons { text-align:right; margin-top:6px; }',
            '  .cputemp-settings-buttons button { padding:5px 18px; margin-left:8px; cursor:pointer; border-radius:4px; font-size:13px; font-weight:bold; }',
            '  .cputemp-cancel { border:1px solid #ccc; background-color:#fff; color:#555; }',
            '  .cputemp-cancel:hover { border:1px solid #aaa; background-color:#f0f0f0; }',
            '  .cputemp-save { border:1px solid #1B8AED; background-color:#1B8AED; color:#fff; }',
            '  .cputemp-save:hover { border:1px solid #057FEB; background-color:#057FEB; }',
            '  .cputemp-settings-status { font-size:12px; color:#888; min-height:16px; }',
            '</style>',
            '<div class="cputemp-body">',
            '  <div class="cputemp-toolbar">',
            '    <button type="button" class="cputemp-refresh">Refresh</button>',
            '    <button type="button" class="cputemp-clear">Clear</button>',
            '    <button type="button" class="cputemp-settings">Settings</button>',
            '    <span class="cputemp-status"></span>',
            '  </div>',
            '  <pre class="cputemp-log">Loading&hellip;</pre>',
            '  <div class="cputemp-modal-backdrop">',
            '    <div class="cputemp-modal">',
            '      <button type="button" class="cputemp-modal-close" aria-label="Close">\u00d7</button>',
            '      <div class="cputemp-row">',
            '        <label><input type="checkbox" class="cputemp-log-enabled"> Enable logging</label>',
            '      </div>',
            '      <div class="cputemp-row">',
            '        <label>Days to keep in log:</label>',
            '        <input type="number" min="1" max="365" class="cputemp-log-days" style="width:60px">',
            '      </div>',
            '      <div class="cputemp-row">',
            '        <label>Log frequency:</label>',
            '        <select class="cputemp-frequency">',
            '          <option value="1">Every hour</option>',
            '          <option value="2">Every 2 hours</option>',
            '          <option value="3">Every 3 hours</option>',
            '          <option value="4">Every 4 hours</option>',
            '          <option value="5">Every 5 hours</option>',
            '          <option value="6">Every 6 hours</option>',
            '          <option value="7">Every 7 hours</option>',
            '          <option value="8">Every 8 hours</option>',
            '          <option value="9">Every 9 hours</option>',
            '          <option value="10">Every 10 hours</option>',
            '          <option value="11">Every 11 hours</option>',
            '        </select>',
            '      </div>',
            '      <div class="cputemp-row cputemp-settings-status"></div>',
            '      <div class="cputemp-row cputemp-settings-buttons">',
            '        <button type="button" class="cputemp-cancel">Cancel</button>',
            '        <button type="button" class="cputemp-save">Save</button>',
            '      </div>',
            '    </div>',
            '  </div>',
            '</div>'
        ].join("");
    },

    onAfterRender: function() {
        var el = this.body.dom;
        this.logEl = el.querySelector(".cputemp-log");
        this.statusEl = el.querySelector(".cputemp-status");
        this.backdropEl = el.querySelector(".cputemp-modal-backdrop");
        this.enabledEl = el.querySelector(".cputemp-log-enabled");
        this.daysEl = el.querySelector(".cputemp-log-days");
        this.freqEl = el.querySelector(".cputemp-frequency");
        this.settingsStatusEl = el.querySelector(".cputemp-settings-status");

        Ext.fly(el.querySelector(".cputemp-refresh")).on("click", this.runAndLoad, this);
        Ext.each(el.querySelectorAll(".cputemp-clear"), function(btn) {
            Ext.fly(btn).on("click", this.clearLog, this);
        }, this);
        Ext.fly(el.querySelector(".cputemp-settings")).on("click", this.openSettings, this);
        Ext.fly(el.querySelector(".cputemp-modal-close")).on("click", this.closeSettings, this);
        Ext.fly(el.querySelector(".cputemp-cancel")).on("click", this.closeSettings, this);
        Ext.fly(el.querySelector(".cputemp-save")).on("click", this.onSaveSettings, this);
        // Click on the dimmed backdrop (but not the modal box itself) also cancels.
        Ext.fly(this.backdropEl).on("click", function(ev) {
            if (ev.getTarget() === this.backdropEl) { this.closeSettings(); }
        }, this);

        // DSM's desktop chrome suppresses the native right-click menu
        // globally (likely a document-level listener, same instinct as
        // the user-select:none override above). Stopping propagation
        // here keeps it from reaching that handler, so Copy etc. shows
        // up normally over our own content.
        Ext.fly(el).on("contextmenu", function(ev) { ev.stopPropagation(); });

        this.runAndLoad();
    },

    setStatus: function(msg) {
        if (this.statusEl) { this.statusEl.textContent = msg || ""; }
    },

    setSettingsStatus: function(msg) {
        if (this.settingsStatusEl) { this.settingsStatusEl.textContent = msg || ""; }
    },

    // Runs syno_cpu_temp.sh (writes/updates the log if logging is on),
    // then fetches the log contents to display.
    runAndLoad: function() {
        this.setStatus("Running\u2026");
        SYNO.SDS.CPUTemp.apiCall("run", {}, (function(resp) {
            if (!resp || !resp.success) {
                this.setStatus((resp && resp.message) || "Failed to run script");
                return;
            }
            this.loadLog();
        }).createDelegate(this));
    },

    loadLog: function() {
        SYNO.SDS.CPUTemp.apiCall("getlog", {}, (function(resp) {
            this.setStatus("");
            if (resp && resp.success) {
                this.showLog(resp.result);
            } else {
                this.showLog((resp && resp.message) || "(no log available)");
            }
        }).createDelegate(this));
    },

    showLog: function(text) {
        if (this.logEl) {
            this.logEl.textContent = text || "(log is empty)";
            this.logEl.scrollTop = this.logEl.scrollHeight;
        }
    },

    clearLog: function() {
        this.setStatus("Clearing\u2026");
        SYNO.SDS.CPUTemp.apiCall("clearlog", {}, (function(resp) {
            if (resp && resp.success) {
                this.runAndLoad();
            } else {
                this.setStatus((resp && resp.message) || "Failed to clear log");
            }
        }).createDelegate(this));
    },

    openSettings: function() {
        this.setSettingsStatus("");
        SYNO.SDS.CPUTemp.apiCall("getsettings", {}, (function(resp) {
            if (resp && resp.success) {
                this.enabledEl.checked = !!resp.log_enabled;
                this.daysEl.value = resp.log_days || 7;
                this.freqEl.value = resp.frequency || "1";
            } else {
                this.enabledEl.checked = false;
                this.daysEl.value = "";
                this.freqEl.selectedIndex = 0;
                this.setSettingsStatus((resp && resp.message) || "Could not load settings");
            }
            Ext.fly(this.backdropEl).addClass("open");
        }).createDelegate(this));
    },

    closeSettings: function() {
        Ext.fly(this.backdropEl).removeClass("open");
    },

    onSaveSettings: function() {
        this.setSettingsStatus("Saving\u2026");
        SYNO.SDS.CPUTemp.apiCall("setsettings", {
            log_enabled: this.enabledEl.checked ? "yes" : "no",
            log_days: this.daysEl.value,
            frequency: this.freqEl.value
        }, (function(resp) {
            if (resp && resp.success) {
                this.setSettingsStatus("");
                this.closeSettings();
                this.loadLog();
            } else {
                this.setSettingsStatus((resp && resp.message) || "Failed to save settings");
            }
        }).createDelegate(this));
    },

    onClose: function() {
        SYNO.SDS.CPUTemp.MainWindow.superclass.onClose.apply(this, arguments);
        this.doClose();
        return true;
    }
});
