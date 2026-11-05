<p align="center">
  <img src="docs/icon.png" width="128" alt="ALS Downgrade icon">
</p>

<h1 align="center">ALS Downgrade</h1>

<p align="center">
  <b>Open newer Ableton Live projects in the older version you have.</b><br>
  Free macOS app. Your original file is never changed.
</p>

<p align="center">
  <a href="https://github.com/SirAI-stack/als-downgrade/releases/latest"><b>Download for Mac</b></a>
</p>

<p align="center">
  <img src="docs/idle.png" width="250" alt="Drop a project">
  &nbsp;&nbsp;
  <img src="docs/done.png" width="250" alt="Project converted">
  &nbsp;&nbsp;
  <img src="docs/info.png" width="170" alt="Supported versions">
</p>

Got **"this Set was created with a newer version of Live"**? ALS Downgrade converts an Ableton Live Set (`.als`) saved with a newer Live version into a Set your installed Live can open.

## Why it is different

Most guides tell you to edit the version number inside the `.als`. That is often not enough: Live refuses classes it does not know, and can crash after loading. ALS Downgrade instead reads the format schemas shipped inside your own copy of Live and rewrites the project to match them.

- Removes what your version does not understand and adds the fields it requires
- Keeps tracks, clips, MIDI notes, automation and tempo
- Relinks your collected audio from the project `Samples` folder
- Tells you about anything it had to remove
- Accepts a single `.als` or a whole project folder
- Opens the result in Live and confirms that it loaded

## Compatibility

| From | To | Status |
|---|---|---|
| Live 12.4 | Live 12.0.20 | Tested in Live with real projects |
| Other Live 12 versions | An older Live 12 | Expected to work, not tested |
| Live 12 | Live 10 or 11 | Experimental, command line only, may not open |
| Anything | Live 9 or older | Not supported |

Newer features cannot be carried back. Devices that do not exist in your version are removed, and third-party plugins must be installed. Back up important work.

## Download

1. Download **[ALS-Downgrade-1.0.dmg](https://github.com/SirAI-stack/als-downgrade/releases/latest)**.
2. Open it and drag **ALS Downgrade** to **Applications**.
3. First launch: macOS warns that the app is from an unidentified developer. Try to open it once, then go to **System Settings > Privacy & Security** and click **Open Anyway**.
4. Drop your `.als` or project folder on the window.

Works on Apple Silicon and Intel Macs, macOS 11 or later. If Apple's free Command Line Tools are missing, the app asks macOS to install them. Keep the `.als` inside its project folder so audio can be found.

## Build from source

```bash
git clone https://github.com/SirAI-stack/als-downgrade.git
cd als-downgrade
./build.sh
```

## Command line

```bash
python3 als_downgrade.py "Song Project/"
python3 als_downgrade.py "Song.als" --check
```

## En español

**¿Tu Ableton dice que el proyecto se creó con una versión más nueva?** Suelta el `.als` o la carpeta del proyecto en ALS Downgrade y ábrelo en tu versión de Live. El archivo original no se modifica. Probado de Live 12.4 a Live 12.0.20.

## Keywords

Ableton Live downgrade, open als in older version, als converter, Live 12 to Live 11, newer version of Live error, backwards compatible Ableton project.

## Credits

By Carni. MIT License.

ALS Downgrade is an independent project, not affiliated with or endorsed by Ableton AG. Ableton and Live are trademarks of Ableton AG.
