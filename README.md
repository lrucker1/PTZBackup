# PTZBackup
PTZ Backup is a Mac utility app to simplify backup and restoration of PTZOptics camera scenes. It uses libvisca in TCP mode.

The PTZOptics camera control app manages 9 scene presets for up to 8 PTZOptics cameras. The cameras support up to 90 scenes; this app lets you use those scenes as backup locations for the standard 9.

How to use:

Enter an offset where your scenes will be backed up - for example, an offset of 80 will backup scenes 1-9 at 81-89. In Single mode, you can backup or restore individual scenes, or use Check mode to quickly cycle through the current scenes for verification. Batch mode will copy all the scenes for the selected camera or all cameras.


In Batch mode you can also make a backup of the settings.ini file, and use it to restore individual scene names or replace the entire settings.ini file (caution recommended with this option)

Setting a scene will automatically save a snapshot image to the PTZOptics ‘downloads’ folder.

Other features include generating HTTP-CGI URLs to set the camera's PTZ values.
