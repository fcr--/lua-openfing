# lua-openfing
Video player for OpenFING (made in lua)

## Installation:
```sh
sudo apt-get install luajit lua-lgi gir1.2-gstreamer-1.0 gir1.2-soup-2.4 gir1.2-gtk-3.0 gstreamer1.0-plugins-good gstreamer1.0-libav
git clone https://github.com/fcr--/lua-openfing.git
```

## Usage
```sh
cd lua-openfing
./app.lua
```

## Bibliography
* Gtk: [reference](https://developer.gnome.org/gtk3/stable/gtkobjects.html), [sorted treeview example](https://bloerg.net/2012/10/23/sorted-and-filtered-tree-view.html),
* GStreamer: [reference](https://gstreamer.freedesktop.org/data/doc/gstreamer/head/gstreamer/html/), [gui integration tutorial](https://gstreamer.freedesktop.org/documentation/tutorials/basic/toolkit-integration.html).
* libsoup: [docs](https://developer.gnome.org/libsoup/stable/libsoup-client-howto.html)
* lgi: [guide](https://github.com/pavouk/lgi/blob/master/docs/guide.md), [treeview example](https://github.com/pavouk/lgi/blob/master/samples/gtk-demo/demo-treeview-liststore.lua), [stockbrowser example](https://github.com/pavouk/lgi/blob/master/samples/gtk-demo/demo-stockbrowser.lua), [get_xid method](https://github.com/pavouk/lgi/issues/6#issuecomment-5302793).
* OpenFING: [public api](https://open.fing.edu.uy/data/).
* Lua: [reference](https://www.lua.org/manual/5.1/manual.html).
