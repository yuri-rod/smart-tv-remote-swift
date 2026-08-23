# VHS Tape for smartcast
# Run: vhs demo.tape

Output assets/demo.gif
Output assets/demo.svg

Set FontSize 16
Set Width 900
Set Height 520
Set Theme "Catppuccin Mocha"
Set Padding 20

Type "smartcast scan"
Enter
Sleep 4s

Type "smartcast key 192.168.1.50 volup"
Enter
Sleep 1.5s

Type "smartcast text 192.168.1.50 'Interstellar 4K'"
Enter
Sleep 1.5s

Type "smartcast cast 192.168.1.50 http://192.168.1.100:8096/stream.mp4"
Enter
Sleep 3s
