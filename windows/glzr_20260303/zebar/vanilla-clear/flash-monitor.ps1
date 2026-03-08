# Flash Monitor - Detects taskbar flashing windows using Shell Hooks
# Writes current flashing apps to flash-state.json

Add-Type @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

public class FlashMonitor {
    // Excluded processes - add process names here to ignore them
    static HashSet<string> excludedProcesses = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
        "msrdc",           // Remote Desktop
        "mstsc",           // Remote Desktop Connection
        "explorer",        // Windows Explorer
        "zebar",           // Zebar itself
        "powershell",      // PowerShell
        "cmd"              // Command Prompt
    };
    [DllImport("user32.dll")]
    static extern bool RegisterShellHookWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    static extern bool DeregisterShellHookWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    static extern uint RegisterWindowMessage(string lpString);

    [DllImport("user32.dll")]
    static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();

    [DllImport("kernel32.dll")]
    static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr hObject);

    [DllImport("psapi.dll")]
    static extern uint GetModuleFileNameEx(IntPtr hProcess, IntPtr hModule, StringBuilder lpBaseName, int nSize);

    const int HSHELL_FLASH = 0x8006;  // 32774 - Window is flashing
    const int HSHELL_REDRAW = 6;       // Window needs redraw (sometimes clears flash)
    const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    static Dictionary<IntPtr, FlashInfo> flashingWindows = new Dictionary<IntPtr, FlashInfo>();
    static string outputPath;
    static object lockObj = new object();
    static JavaScriptSerializer serializer = new JavaScriptSerializer();

    public class FlashInfo {
        public string title;
        public string processName;
        public DateTime flashTime;
    }

    public static void WriteState() {
        lock (lockObj) {
            var result = new Dictionary<string, object>();
            var apps = new List<Dictionary<string, string>>();

            // Clean up old flashes (older than 30 seconds with no refresh)
            var now = DateTime.Now;
            var toRemove = new List<IntPtr>();
            foreach (var kvp in flashingWindows) {
                if ((now - kvp.Value.flashTime).TotalSeconds > 30) {
                    toRemove.Add(kvp.Key);
                }
            }
            foreach (var key in toRemove) {
                flashingWindows.Remove(key);
            }

            foreach (var kvp in flashingWindows) {
                var app = new Dictionary<string, string>();
                app["title"] = kvp.Value.title;
                app["process"] = kvp.Value.processName;
                apps.Add(app);
            }

            result["hasNotifications"] = apps.Count > 0;
            result["apps"] = apps;
            result["count"] = apps.Count;

            try {
                File.WriteAllText(outputPath, serializer.Serialize(result));
            } catch { }
        }
    }

    public static string GetProcessName(IntPtr hWnd) {
        uint processId;
        GetWindowThreadProcessId(hWnd, out processId);
        IntPtr hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
        if (hProcess != IntPtr.Zero) {
            StringBuilder sb = new StringBuilder(1024);
            if (GetModuleFileNameEx(hProcess, IntPtr.Zero, sb, sb.Capacity) > 0) {
                CloseHandle(hProcess);
                string path = sb.ToString();
                return System.IO.Path.GetFileNameWithoutExtension(path);
            }
            CloseHandle(hProcess);
        }
        return "unknown";
    }

    public static string GetWindowTitle(IntPtr hWnd) {
        StringBuilder sb = new StringBuilder(256);
        GetWindowText(hWnd, sb, 256);
        return sb.ToString();
    }

    public static void OnFlash(IntPtr hWnd) {
        // Don't track the foreground window (it's not really "needing attention")
        if (hWnd == GetForegroundWindow()) return;

        lock (lockObj) {
            var info = new FlashInfo();
            info.title = GetWindowTitle(hWnd);
            info.processName = GetProcessName(hWnd);
            info.flashTime = DateTime.Now;

            // Skip excluded processes
            if (excludedProcesses.Contains(info.processName)) return;

            if (!string.IsNullOrEmpty(info.title)) {
                flashingWindows[hWnd] = info;
            }
        }
        WriteState();
    }

    public static void OnActivate(IntPtr hWnd) {
        // When a window is activated/focused, it's no longer "flashing"
        lock (lockObj) {
            if (flashingWindows.ContainsKey(hWnd)) {
                flashingWindows.Remove(hWnd);
            }
        }
        WriteState();
    }

    public static void Initialize(string path) {
        outputPath = path;
        WriteState();
    }

    public static int GetFlashMessage() {
        return HSHELL_FLASH;
    }
}
'@ -ReferencedAssemblies "System.Web.Extensions"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputPath = Join-Path $scriptDir "flash-state.json"

[FlashMonitor]::Initialize($outputPath)

# Create a simple message-only window to receive shell hook messages
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class ShellHookWindow : Form {
    [DllImport("user32.dll")]
    public static extern bool RegisterShellHookWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool DeregisterShellHookWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern uint RegisterWindowMessage(string lpString);

    public static uint WM_SHELLHOOKMESSAGE;
    public Action<int, IntPtr> OnShellHook;

    const int WS_EX_TOOLWINDOW = 0x80;

    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= WS_EX_TOOLWINDOW;  // Hide from Alt+Tab
            return cp;
        }
    }

    public ShellHookWindow() {
        this.ShowInTaskbar = false;
        this.FormBorderStyle = FormBorderStyle.None;
        this.Size = new System.Drawing.Size(0, 0);
        this.Opacity = 0;
        this.Load += (s, e) => {
            this.Visible = false;
            WM_SHELLHOOKMESSAGE = RegisterWindowMessage("SHELLHOOK");
            RegisterShellHookWindow(this.Handle);
        };
        this.FormClosing += (s, e) => {
            DeregisterShellHookWindow(this.Handle);
        };
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_SHELLHOOKMESSAGE && OnShellHook != null) {
            OnShellHook((int)m.WParam, m.LParam);
        }
        base.WndProc(ref m);
    }
}
'@ -ReferencedAssemblies "System.Windows.Forms", "System.Drawing"

$form = New-Object ShellHookWindow
$form.OnShellHook = {
    param($code, $hwnd)
    if ($code -eq 0x8006) {  # HSHELL_FLASH
        [FlashMonitor]::OnFlash($hwnd)
    }
    elseif ($code -eq 4) {  # HSHELL_WINDOWACTIVATED
        [FlashMonitor]::OnActivate($hwnd)
    }
}

Write-Host "Flash monitor started. Output: $outputPath"
Write-Host "Press Ctrl+C to stop."

[System.Windows.Forms.Application]::Run($form)
