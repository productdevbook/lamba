#!/usr/bin/env python3
"""Single source of truth for UI translations. Generates Support/Localization/<lang>.lproj/Localizable.strings.

Usage: python3 scripts/strings.py
"""
import os

LANGS = ["en", "tr", "de"]

# key: (English, Turkish, German)
STRINGS = {
    "fixConnection": ("Fix connection", "Bağlantıyı onar", "Verbindung reparieren"),

    "light.green": ("Green", "Yeşil", "Grün"),
    "light.orange": ("Orange", "Turuncu", "Orange"),
    "light.off": ("Off", "Kapalı", "Aus"),
    "light.automatic": ("Auto", "Otomatik", "Auto"),
    "light.slow": ("Slow", "Yavaş", "Langsam"),
    "light.fast": ("Fast", "Hızlı", "Schnell"),
    "light.alternate": ("Alternate", "Sırayla", "Wechseln"),
    "mode.blinkSlow": ("Slow blink", "Yavaş yanıp sönme", "Langsames Blinken"),
    "mode.blinkFast": ("Fast blink", "Hızlı yanıp sönme", "Schnelles Blinken"),
    "mode.alternate": ("Green / Orange", "Yeşil / Turuncu", "Grün / Orange"),
    "resetLight": ("Set light to Auto", "Işığı otomatiğe al", "Licht auf Auto stellen"),

    "pomodoro.start": ("Start", "Başlat", "Starten"),
    "pomodoro.startMenu": ("Start Pomodoro", "Pomodoro başlat", "Pomodoro starten"),
    "pomodoro.pause": ("Pause", "Duraklat", "Pausieren"),
    "pomodoro.resume": ("Resume", "Devam et", "Fortsetzen"),
    "pomodoro.skip": ("Skip to next phase", "Sonraki aşamaya geç", "Zur nächsten Phase"),
    "pomodoro.stop": ("Stop Pomodoro", "Pomodoro'yu durdur", "Pomodoro beenden"),
    "pomodoro.paused": ("Paused", "Duraklatıldı", "Pausiert"),
    "phase.work": ("Focus", "Odaklan", "Fokus"),
    "phase.shortBreak": ("Short break", "Kısa mola", "Kurze Pause"),
    "phase.longBreak": ("Long break", "Uzun mola", "Lange Pause"),
    "sessions.first": ("First session", "İlk oturum", "Erste Sitzung"),
    "sessions.completed": ("%d completed", "%d tamamlandı", "%d abgeschlossen"),

    "settings": ("Settings", "Ayarlar", "Einstellungen"),
    "settings.title": ("Lamba Settings", "Lamba Ayarları", "Lamba-Einstellungen"),
    "settings.general": ("General", "Genel", "Allgemein"),
    "settings.integrations": ("Integrations", "Entegrasyonlar", "Integrationen"),
    "settings.about": ("About", "Hakkında", "Über"),
    "launchAtLogin": ("Open at login", "Mac açılınca başlat", "Bei Anmeldung öffnen"),
    "launchAtLoginFailed": ("Could not change login item", "Girişte başlatma ayarlanamadı", "Anmeldeobjekt konnte nicht geändert werden"),
    "language": ("Language", "Dil", "Sprache"),
    "language.system": ("System", "Sistem", "System"),
    "language.restartHint": ("Lamba restarts to apply the language.", "Dilin uygulanması için Lamba yeniden başlar.", "Lamba startet neu, um die Sprache anzuwenden."),
    "language.restart": ("Restart now", "Şimdi yeniden başlat", "Jetzt neu starten"),
    "defaultDuration": ("Default duration", "Varsayılan süre", "Standarddauer"),
    "longBreak": ("Long break", "Uzun mola", "Lange Pause"),
    "sessionsBeforeLongBreak": ("Sessions before long break", "Uzun moladan önceki oturum", "Sitzungen bis zur langen Pause"),
    "playSounds": ("Play a sound on phase change", "Aşama değişince ses çal", "Ton bei Phasenwechsel"),
    "flashOnPhaseChange": ("Flash the light on phase change", "Aşama değişince ışığı yanıp söndür", "Licht bei Phasenwechsel blinken"),
    "minutes": ("%d min", "%d dk", "%d Min."),
    "preset": ("%1$d min focus / %2$d min break", "%1$d dk çalışma / %2$d dk mola", "%1$d Min. Fokus / %2$d Min. Pause"),

    "copy": ("Copy", "Kopyala", "Kopieren"),
    "copied": ("Copied", "Kopyalandı", "Kopiert"),
    "claudeCode.caption": ("Run in Terminal so Claude can control the light.", "Terminalde çalıştırın; Claude ışığı kontrol edebilir.", "Im Terminal ausführen, damit Claude das Licht steuern kann."),
    "claudeDesktop.caption": ("Settings › Developer › Edit Config", "Ayarlar › Geliştirici › Yapılandırmayı düzenle", "Einstellungen › Entwickler › Konfiguration bearbeiten"),
    "hooks.title": ("Claude Code notifications", "Claude Code bildirimleri", "Claude Code-Benachrichtigungen"),
    "hooks.caption": (
        "Shows Claude's status in the Dock and flashes the LED. Install adds these to ~/.claude/settings.json (a backup is kept).",
        "Claude'un durumunu Dock'ta gösterir ve LED'i yakıp söndürür. Kur, bunları ~/.claude/settings.json'a ekler (yedek alınır).",
        "Zeigt Claudes Status im Dock und lässt die LED blinken. Installieren fügt dies zu ~/.claude/settings.json hinzu (mit Sicherung).",
    ),
    "hooks.install": ("Install", "Kur", "Installieren"),
    "hooks.installed": ("Installed in Claude Code", "Claude Code'a kuruldu", "In Claude Code installiert"),
    "hooks.installFailed": ("Couldn't update Claude Code settings", "Claude Code ayarları güncellenemedi", "Claude Code-Einstellungen konnten nicht geändert werden"),
    "agent.working": ("Working", "Çalışıyor", "Arbeitet"),
    "agent.workingMany": ("%d Claude sessions working", "%d Claude oturumu çalışıyor", "%d Claude-Sitzungen arbeiten"),
    "agent.waiting": ("Needs you", "Seni bekliyor", "Wartet"),
    "agent.done": ("Done", "Bitti", "Fertig"),
    "agent.session": ("Claude session", "Claude oturumu", "Claude-Sitzung"),
    "agent.thisMac": ("This Mac", "Bu Mac", "Dieser Mac"),
    "agent.finished": ("%@ finished", "%@ bitti", "%@ ist fertig"),
    "agent.connected": ("connected", "bağlı", "verbunden"),
    "agent.offline": ("not connected", "bağlı değil", "nicht verbunden"),
    "agent.noSessions": ("No Claude sessions", "Claude oturumu yok", "Keine Claude-Sitzungen"),
    "agent.ago": ("%@ ago", "%@ önce", "vor %@"),
    "agent.tool.edit": ("Editing", "Düzenliyor", "Bearbeitet"),
    "agent.tool.read": ("Reading", "Okuyor", "Liest"),
    "agent.tool.bash": ("Command", "Komut", "Befehl"),
    "agent.tool.search": ("Searching", "Arıyor", "Sucht"),
    "agent.tool.web": ("Web", "Web", "Web"),
    "agent.tool.agent": ("Subagent", "Alt ajan", "Subagent"),
    "agent.tool.plan": ("Planning", "Plan yapıyor", "Plant"),
    "agent.tool.other": ("%@", "%@", "%@"),
    "permission.title": ("%@?", "%@?", "%@?"),
    "permission.allow": ("Allow", "İzin ver", "Erlauben"),
    "permission.deny": ("Deny", "Reddet", "Ablehnen"),
    "permission.ask": ("Ask in terminal", "Terminalde sor", "Im Terminal fragen"),
    "music.next": ("Next track", "Sonraki şarkı", "Nächster Titel"),
    "music.previous": ("Previous track", "Önceki şarkı", "Vorheriger Titel"),
    "music.open": ("Open %@", "%@ uygulamasını aç", "%@ öffnen"),
    "meeting.now": ("Now", "Şimdi", "Jetzt"),
    "meeting.in": ("in %d min", "%d dk sonra", "in %d Min."),
    "meeting.join": ("Join", "Katıl", "Beitreten"),
    "meeting.openCalendar": ("Open in Calendar", "Takvim'de aç", "Im Kalender öffnen"),
    "cli.title": ("Command line", "Komut satırı", "Befehlszeile"),
    "cli.caption": ("Use from scripts and builds.", "Betiklerden ve derlemelerden kullanın.", "Aus Skripten und Builds verwenden."),

    "version": ("Version %@", "Sürüm %@", "Version %@"),
    "helper.section": ("Helper service", "Yardımcı servis", "Hilfsdienst"),
    "helper.status": ("Status", "Durum", "Status"),
    "helper.running": ("Running", "Çalışıyor", "Läuft"),
    "helper.notRunning": ("Helper is not running", "Yardımcı servis çalışmıyor", "Hilfsdienst läuft nicht"),
    "cli.location": ("Command line tool", "Komut satırı aracı", "Befehlszeilen-Tool"),
    "reinstall": ("Reinstall", "Yeniden kur", "Neu installieren"),
    "uninstall": ("Uninstall…", "Kaldır…", "Deinstallieren…"),
    "uninstall.confirm": ("Uninstall Lamba?", "Lamba kaldırılsın mı?", "Lamba deinstallieren?"),
    "uninstall.detail": (
        "The helper service and the lamba command are removed and the light goes back to macOS. Then move Lamba.app to the Trash.",
        "Yardımcı servis ve lamba komutu silinir, ışık macOS'a bırakılır. Ardından Lamba.app'i çöp kutusuna atabilirsiniz.",
        "Der Hilfsdienst und der Befehl lamba werden entfernt, das Licht wird wieder von macOS gesteuert. Danach Lamba.app in den Papierkorb legen.",
    ),
    "uninstall.prompt": ("Lamba wants to remove its helper service.", "Lamba, yardımcı servisini kaldırmak istiyor.", "Lamba möchte seinen Hilfsdienst entfernen."),
    "uninstall.failed": ("Uninstall failed", "Kaldırma tamamlanamadı", "Deinstallation fehlgeschlagen"),
    "cancel": ("Cancel", "Vazgeç", "Abbrechen"),

    "quit": ("Quit Lamba", "Lamba'ten çık", "Lamba beenden"),
    "install.prompt": (
        "Lamba needs a one-time setup to control the charging light.",
        "Lamba, şarj ışığını kontrol edebilmek için bir kerelik kurulum yapmak istiyor.",
        "Lamba benötigt eine einmalige Einrichtung, um die Ladeleuchte zu steuern.",
    ),
    "install.failed": ("Setup could not be completed", "Kurulum tamamlanamadı", "Einrichtung fehlgeschlagen"),
    "server.failed": ("Could not start the command line connection", "Komut satırı bağlantısı başlatılamadı", "Befehlszeilenverbindung konnte nicht gestartet werden"),
    "settings.statistics": ("Statistics", "İstatistikler", "Statistik"),
    "range.days": ("%d days", "%d gün", "%d Tage"),
    "export": ("Export", "Dışa aktar", "Exportieren"),
    "export.csv": ("Save as CSV…", "CSV olarak kaydet…", "Als CSV sichern…"),
    "export.copy": ("Copy summary", "Özeti kopyala", "Zusammenfassung kopieren"),
    "kpi.focus": ("Focus time", "Odak süresi", "Fokuszeit"),
    "kpi.sessions": ("Sessions", "Oturum", "Sitzungen"),
    "kpi.streak": ("Streak", "Seri", "Serie"),
    "kpi.flashes": ("Notifications", "Bildirim", "Benachrichtigungen"),
    "delta.vsPrevious": ("%@ vs previous", "öncekine göre %@", "%@ ggü. vorher"),
    "streak.days": ("%d days", "%d gün", "%d Tage"),
    "chart.dailyFocus": ("Daily focus", "Günlük odak", "Täglicher Fokus"),
    "chart.average": ("Average %@ per day", "Günde ortalama %@", "Durchschnittlich %@ pro Tag"),
    "chart.minutes": ("Minutes", "Dakika", "Minuten"),
    "usage.light": ("Light", "Işık", "Licht"),
    "usage.charger": ("Charger", "Şarj", "Ladegerät"),
    "charge.charging": ("Charging", "Şarj oluyor", "Lädt"),
    "charge.plugged": ("Plugged in, not charging", "Takılı, şarj olmuyor", "Angeschlossen, lädt nicht"),
    "charge.battery": ("On battery", "Pilde", "Akkubetrieb"),
    "stats.empty": (
        "No focus time yet. Start a Pomodoro and it shows up here.",
        "Henüz odak süresi yok. Bir Pomodoro başlatınca burada görünecek.",
        "Noch keine Fokuszeit. Starte einen Pomodoro, dann erscheint sie hier.",
    ),
    "stats.privacy": ("Statistics are stored only on this Mac.", "İstatistikler yalnızca bu Mac'te saklanır.", "Statistiken werden nur auf diesem Mac gespeichert."),
    "stats.clear": ("Clear history…", "Geçmişi sil…", "Verlauf löschen…"),
    "stats.clear.confirm": ("Clear all statistics?", "Tüm istatistikler silinsin mi?", "Alle Statistiken löschen?"),
    "stats.clear.detail": ("This cannot be undone.", "Bu işlem geri alınamaz.", "Das kann nicht rückgängig gemacht werden."),
    "stats.clear.action": ("Clear", "Sil", "Löschen"),
    "onboarding.title": ("Welcome to Lamba", "Lamba'ya hoş geldiniz", "Willkommen bei Lamba"),
    "onboarding.subtitle": ("Your charging light becomes a status light.", "Şarj ışığınız bir durum ışığına dönüşüyor.", "Deine Ladeleuchte wird zur Statusleuchte."),
    "onboarding.light.title": ("Control the light", "Işığı yönetin", "Licht steuern"),
    "onboarding.light.body": ("Green, orange, off or blinking, right from the menu bar.", "Yeşil, turuncu, kapalı ya da yanıp sönen; menü çubuğundan.", "Grün, Orange, aus oder blinkend, direkt aus der Menüleiste."),
    "onboarding.pomodoro.title": ("Focus with Pomodoro", "Pomodoro ile odaklanın", "Fokus mit Pomodoro"),
    "onboarding.pomodoro.body": ("The light shows when to work and when to rest.", "Işık ne zaman çalışıp ne zaman dinleneceğinizi gösterir.", "Das Licht zeigt, wann Arbeit und wann Pause ist."),
    "onboarding.claude.title": ("Connect Claude", "Claude'u bağlayın", "Claude verbinden"),
    "onboarding.claude.body": ("Get a signal when Claude finishes or needs you.", "Claude işini bitirince ya da sizi beklerken haber alın.", "Werde benachrichtigt, wenn Claude fertig ist oder dich braucht."),
    "onboarding.password": (
        "Lamba asks for your password once to install a small helper. It can only change the charging light.",
        "Lamba, küçük bir yardımcı servis kurmak için şifrenizi bir kez ister. Bu servis yalnızca şarj ışığını değiştirebilir.",
        "Lamba fragt einmal nach deinem Passwort, um einen kleinen Hilfsdienst zu installieren. Er kann nur die Ladeleuchte ändern.",
    ),
    "onboarding.install": ("Install and start", "Kur ve başla", "Installieren und starten"),
    "onboarding.later": ("Later", "Sonra", "Später"),
    "onboarding.done.title": ("You're all set", "Hazırsınız", "Alles bereit"),
    "onboarding.done.body": ("Click the bolt in the menu bar to get started.", "Başlamak için menü çubuğundaki şimşeğe tıklayın.", "Klicke auf den Blitz in der Menüleiste, um loszulegen."),
    "onboarding.done": ("Done", "Bitti", "Fertig"),
    "unsupported.title": ("No MagSafe light found", "MagSafe ışığı bulunamadı", "Keine MagSafe-Leuchte gefunden"),
    "unsupported.body": (
        "Lamba needs a Mac with a MagSafe 3 port to control the light. Pomodoro and statistics still work.",
        "Işığı kontrol etmek için MagSafe 3 girişi olan bir Mac gerekir. Pomodoro ve istatistikler yine de çalışır.",
        "Zum Steuern des Lichts braucht Lamba einen Mac mit MagSafe 3-Anschluss. Pomodoro und Statistik funktionieren trotzdem.",
    ),
    "unsupported.short": ("No MagSafe", "MagSafe yok", "Kein MagSafe"),
    "continue": ("Continue", "Devam et", "Weiter"),
    "haptics": ("Vibrate on notifications and phase changes", "Bildirimlerde ve aşama değişince titret", "Bei Benachrichtigungen und Phasenwechsel vibrieren"),
    "haptics.test": ("Test", "Dene", "Testen"),
    "haptics.section": ("Vibration", "Titreşim", "Vibration"),
    "haptics.waveform": ("Waveform", "Dalga tipi", "Wellenform"),
    "haptics.waveform.name": ("Type %d", "Tip %d", "Typ %d"),
    "haptics.waveform.recommended": ("Type %d (recommended)", "Tip %d (önerilen)", "Typ %d (empfohlen)"),
    "haptics.intensity": ("Intensity", "Yoğunluk", "Intensität"),
    "haptics.pulses": ("Repeats", "Tekrar", "Wiederholungen"),
    "haptics.reset": ("Reset to default", "Varsayılana dön", "Zurücksetzen"),
    "haptics.footer": (
        "The trackpad vibrates; you feel it through the case even without touching it.",
        "Trackpad titrer; dokunmasanız bile kasadan hissedilir.",
        "Das Trackpad vibriert; spürbar über das Gehäuse, auch ohne Berührung.",
    ),

    "dock.tab": ("Dock", "Dock", "Dock"),
    "dock.enabled": ("Use Lamba Dock", "Lamba Dock'u kullan", "Lamba Dock verwenden"),
    "dock.hideApple": ("Hide the macOS Dock", "macOS Dock'unu gizle", "macOS-Dock ausblenden"),
    "dock.hideAppleFooter": (
        "Your macOS Dock settings are saved and restored when you turn this off or quit Lamba. Maximized windows can extend under the Lamba Dock.",
        "macOS Dock ayarlarınız kaydedilir; bunu kapattığınızda veya Lamba'dan çıktığınızda geri yüklenir. Tam boyutlu pencereler Lamba Dock'un altına uzanabilir.",
        "Ihre macOS-Dock-Einstellungen werden gesichert und beim Ausschalten oder Beenden von Lamba wiederhergestellt. Maximierte Fenster können unter das Lamba Dock reichen.",
    ),
    "dock.style": ("Style", "Stil", "Stil"),
    "dock.style.strip": ("Strip", "Şerit", "Leiste"),
    "dock.style.islands": ("Islands", "Adalar", "Inseln"),
    "settings.capsLockFlash": ("Blink the Caps Lock light too (only while you're not typing)", "Caps Lock ışığı da yanıp sönsün (yazmıyorken)", "Feststelltaste-Licht ebenfalls blinken lassen (nur wenn Sie nicht tippen)"),
    "settings.keyboardMoods": ("Keyboard light follows Pomodoro and Claude (dim while focusing, breathing on breaks, glowing when Claude needs you)", "Klavye ışığı Pomodoro ve Claude'a uysun (odakta kısık, molada nefes alır, Claude seni beklerken parlar)", "Tastaturlicht folgt Pomodoro und Claude (gedimmt im Fokus, atmend in Pausen, leuchtend, wenn Claude Sie braucht)"),
    "settings.keyboardFlash": ("Blink the keyboard light too", "Klavye ışığı da yanıp sönsün", "Tastaturbeleuchtung ebenfalls blinken lassen"),
    "dock.style.classic": ("Classic", "Klasik", "Klassisch"),
    "dock.style.stripFooter": (
        "A long floating bar: Lamba status and Pomodoro progress, apps, clock and battery.",
        "Uzun, yüzen bir şerit: Lamba durumu ve Pomodoro ilerlemesi, uygulamalar, saat ve pil.",
        "Eine lange, schwebende Leiste: Lamba-Status und Pomodoro-Fortschritt, Apps, Uhr und Akku.",
    ),
    "dock.charge.charging": ("Charging", "Şarj oluyor", "Lädt"),
    "dock.charge.plugged": ("Plugged in", "Takılı", "Angeschlossen"),
    "dock.charge.battery": ("On battery", "Pilde", "Akku"),
    "dock.size": ("Icon size", "Simge boyutu", "Symbolgröße"),
    "dock.magnification": ("Magnification", "Büyütme", "Vergrößerung"),
    "dock.appearance": ("Appearance", "Görünüm", "Darstellung"),
    "dock.apps": ("Apps", "Uygulamalar", "Apps"),
    "dock.reimport": ("Import apps from macOS Dock", "Uygulamaları macOS Dock'tan al", "Apps aus dem macOS-Dock übernehmen"),
    "dock.appsFooter": (
        "Right-click an icon to keep it in the Dock, remove it or move it. Drop files on an app to open them with it.",
        "Simgeye sağ tıklayarak Dock'ta tutabilir, kaldırabilir veya taşıyabilirsiniz. Dosyaları bir uygulamanın üzerine bırakınca onunla açılır.",
        "Klicken Sie mit der rechten Maustaste auf ein Symbol, um es zu behalten, zu entfernen oder zu verschieben. Ziehen Sie Dateien auf eine App, um sie damit zu öffnen.",
    ),
    "dock.open": ("Open", "Aç", "Öffnen"),
    "dock.show": ("Show", "Göster", "Anzeigen"),
    "dock.showInFinder": ("Show in Finder", "Finder'da göster", "Im Finder zeigen"),
    "dock.keep": ("Keep in Dock", "Dock'ta tut", "Im Dock behalten"),
    "dock.remove": ("Remove from Dock", "Dock'tan kaldır", "Aus dem Dock entfernen"),
    "dock.moveLeft": ("Move left", "Sola taşı", "Nach links"),
    "dock.moveRight": ("Move right", "Sağa taşı", "Nach rechts"),
    "dock.hide": ("Hide", "Gizle", "Ausblenden"),
    "dock.quit": ("Quit", "Çık", "Beenden"),
    "dock.trash": ("Trash", "Çöp Sepeti", "Papierkorb"),
    "dock.lambaHelp": (
        "Click to start or pause Pomodoro. Right-click for light options.",
        "Pomodoro'yu başlatmak/duraklatmak için tıklayın. Işık seçenekleri için sağ tıklayın.",
        "Klicken, um Pomodoro zu starten oder zu pausieren. Rechtsklick für Lichtoptionen.",
    ),
}


def load_extra():
    """Each scripts/strings.d/<area>.py defines its own STRINGS dict (same format), merged in."""
    directory = os.path.join(os.path.dirname(os.path.abspath(__file__)), "strings.d")
    for name in sorted(os.listdir(directory)) if os.path.isdir(directory) else []:
        if name.endswith(".py"):
            scope = {}
            with open(os.path.join(directory, name), encoding="utf-8") as f:
                exec(f.read(), scope)
            for key in scope.get("STRINGS", {}):
                assert key not in STRINGS, f"duplicate string key {key} in {name}"
            STRINGS.update(scope.get("STRINGS", {}))


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main():
    load_extra()
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Support", "Localization")
    for index, lang in enumerate(LANGS):
        directory = os.path.join(root, f"{lang}.lproj")
        os.makedirs(directory, exist_ok=True)
        lines = ["/* Generated by scripts/strings.py — edit translations there. */", ""]
        lines += [f'"{key}" = "{escape(values[index])}";' for key, values in sorted(STRINGS.items())]
        with open(os.path.join(directory, "Localizable.strings"), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    print(f"Wrote {len(STRINGS)} strings for {', '.join(LANGS)}")


if __name__ == "__main__":
    main()
