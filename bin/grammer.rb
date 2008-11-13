
require 'gtk2'
require 'yaml'

class GrammerApplet < Gtk::StatusIcon
  def initialize
    super
    self.stock = Gtk::Stock::ABOUT
    self.visible = true

    menu = Gtk::Menu.new
    item_open = Gtk::MenuItem.new("Open")
    item_quit = Gtk::MenuItem.new("Quit")
    item_open.signal_connect("activate") { open_window }
    item_quit.signal_connect("activate") { Gtk.main_quit }
    menu.append(item_open)
    menu.append(item_quit)
    menu.show_all
    signal_connect("activate") do
      open_window
    end

    signal_connect("popup-menu") do |_, button, time|
      menu.popup(nil, nil, button, time)
    end
  end

  def open_window
    GrammerWindow.window ||= GrammerWindow.new
    GrammerWindow.window.show_all
  end
end

class GrammerWindow < Gtk::Window
  class << self
    attr_accessor :window
  end

  def initialize
    super("Grammer")
    signal_connect("destroy") do 
      self.hide_all
      GrammerWindow.window = nil
    end
  end
end

si = GrammerApplet.new
Gtk.main
