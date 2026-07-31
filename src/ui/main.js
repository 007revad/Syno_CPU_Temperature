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
// Main window - runs the script, shows the log
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
            '  .cputemp-body { display:flex; flex-direction:column; height:100%; padding:8px; box-sizing:border-box; }',
            '  .cputemp-toolbar { flex:0 0 auto; padding-bottom:8px; display:flex; align-items:center; gap:8px; }',
            '  .cputemp-toolbar button { padding:4px 10px; cursor:pointer; }',
            '  .cputemp-status { font-size:12px; color:#888; }',
            '  .cputemp-log { flex:1 1 auto; margin:0; overflow:auto; background:#1e1e1e; color:#ddd; padding:8px; font-family:Consolas,Menlo,monospace; font-size:12px; white-space:pre-wrap; border-radius:4px; }',
            '</style>',
            '<div class="cputemp-body">',
            '  <div class="cputemp-toolbar">',
            '    <button type="button" class="cputemp-refresh">Refresh</button>',
            '    <button type="button" class="cputemp-settings">Settings</button>',
            '    <span class="cputemp-status"></span>',
            '  </div>',
            '  <pre class="cputemp-log">Loading&hellip;</pre>',
            '</div>'
        ].join("");
    },

    onAfterRender: function() {
        var el = this.body.dom;
        this.logEl = el.querySelector(".cputemp-log");
        this.statusEl = el.querySelector(".cputemp-status");

        Ext.fly(el.querySelector(".cputemp-refresh")).on("click", this.runAndLoad, this);
        Ext.fly(el.querySelector(".cputemp-settings")).on("click", this.openSettings, this);

        this.runAndLoad();
    },

    setStatus: function(msg) {
        if (this.statusEl) { this.statusEl.textContent = msg || ""; }
    },

    // Runs syno_cpu_temp.sh (writes/updates the log if logging is on),
    // then fetches the log contents to display.
    runAndLoad: function() {
        this.setStatus("Running\u2026");
        SYNO.SDS.CPUTemp.apiCall("run", {}, Ext.bind(function(resp) {
            if (!resp || !resp.success) {
                this.setStatus((resp && resp.message) || "Failed to run script");
                return;
            }
            this.loadLog();
        }, this));
    },

    loadLog: function() {
        SYNO.SDS.CPUTemp.apiCall("getlog", {}, Ext.bind(function(resp) {
            this.setStatus("");
            if (resp && resp.success) {
                this.showLog(resp.result);
            } else {
                this.showLog((resp && resp.message) || "(no log available)");
            }
        }, this));
    },

    showLog: function(text) {
        if (this.logEl) {
            this.logEl.textContent = text || "(log is empty)";
            this.logEl.scrollTop = this.logEl.scrollHeight;
        }
    },

    openSettings: function() {
        new SYNO.SDS.CPUTemp.SettingsWindow({
            mainWindow: this
        }).show();
    },

    onClose: function() {
        SYNO.SDS.CPUTemp.MainWindow.superclass.onClose.apply(this, arguments);
        this.doClose();
        return true;
    }
});

// -----------------------------------------------------------------
// Settings window - logging toggle, days to keep, frequency
// -----------------------------------------------------------------
Ext.define("SYNO.SDS.CPUTemp.SettingsWindow", {
    extend: "SYNO.SDS.AppWindow",

    constructor: function(a) {
        this.mainWindow = a.mainWindow;
        SYNO.SDS.CPUTemp.SettingsWindow.superclass.constructor.call(this, Ext.apply({
            layout: "fit",
            resizable: false,
            cls: "syno-app-win cputemp-settings-win",
            maximizable: false,
            minimizable: false,
            showHelp: false,
            width: 420,
            height: 300,
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
            '  .cputemp-settings-body { padding:16px; box-sizing:border-box; }',
            '  .cputemp-row { margin-bottom:14px; }',
            '  .cputemp-row label { display:inline-block; margin-bottom:4px; }',
            '  .cputemp-settings-buttons { text-align:right; }',
            '  .cputemp-settings-buttons button { padding:5px 14px; margin-left:8px; cursor:pointer; }',
            '  .cputemp-settings-status { font-size:12px; color:#888; min-height:16px; }',
            '</style>',
            '<div class="cputemp-settings-body">',
            '  <div class="cputemp-row">',
            '    <label><input type="checkbox" class="cputemp-log-enabled"> Enable logging</label>',
            '  </div>',
            '  <div class="cputemp-row">',
            '    <label>Days to keep in log:</label>',
            '    <input type="number" min="1" max="365" class="cputemp-log-days" style="width:60px">',
            '  </div>',
            '  <div class="cputemp-row">',
            '    <label>Log frequency:</label>',
            '    <select class="cputemp-frequency">',
            '      <option value="1">Every hour</option>',
            '      <option value="2">Every 2 hours</option>',
            '      <option value="3">Every 3 hours</option>',
            '      <option value="4">Every 4 hours</option>',
            '      <option value="5">Every 5 hours</option>',
            '      <option value="6">Every 6 hours</option>',
            '      <option value="7">Every 7 hours</option>',
            '      <option value="8">Every 8 hours</option>',
            '      <option value="9">Every 9 hours</option>',
            '      <option value="10">Every 10 hours</option>',
            '      <option value="11">Every 11 hours</option>',
            '    </select>',
            '  </div>',
            '  <div class="cputemp-row cputemp-settings-status"></div>',
            '  <div class="cputemp-row cputemp-settings-buttons">',
            '    <button type="button" class="cputemp-save">Save</button>',
            '    <button type="button" class="cputemp-cancel">Cancel</button>',
            '  </div>',
            '</div>'
        ].join("");
    },

    onAfterRender: function() {
        var el = this.body.dom;
        this.enabledEl = el.querySelector(".cputemp-log-enabled");
        this.daysEl = el.querySelector(".cputemp-log-days");
        this.freqEl = el.querySelector(".cputemp-frequency");
        this.statusEl = el.querySelector(".cputemp-settings-status");

        Ext.fly(el.querySelector(".cputemp-save")).on("click", this.onSave, this);
        Ext.fly(el.querySelector(".cputemp-cancel")).on("click", this.close, this);

        this.loadSettings();
    },

    setStatus: function(msg) {
        if (this.statusEl) { this.statusEl.textContent = msg || ""; }
    },

    loadSettings: function() {
        SYNO.SDS.CPUTemp.apiCall("getsettings", {}, Ext.bind(function(resp) {
            if (resp && resp.success && resp.result) {
                this.enabledEl.checked = !!resp.result.log_enabled;
                this.daysEl.value = resp.result.log_days || 7;
                if (resp.result.frequency) {
                    this.freqEl.value = resp.result.frequency;
                }
            } else {
                this.setStatus((resp && resp.message) || "Could not load settings");
            }
        }, this));
    },

    onSave: function() {
        this.setStatus("Saving\u2026");
        SYNO.SDS.CPUTemp.apiCall("setsettings", {
            log_enabled: this.enabledEl.checked ? "yes" : "no",
            log_days: this.daysEl.value,
            frequency: this.freqEl.value
        }, Ext.bind(function(resp) {
            if (resp && resp.success) {
                this.setStatus("Saved");
                setTimeout(Ext.bind(this.close, this), 500);
            } else {
                this.setStatus((resp && resp.message) || "Failed to save settings");
            }
        }, this));
    },

    onClose: function() {
        SYNO.SDS.CPUTemp.SettingsWindow.superclass.onClose.apply(this, arguments);
        this.doClose();
        return true;
    }
});
