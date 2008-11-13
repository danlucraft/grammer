
require 'gtk2'
require 'yaml'

class GrammerApplet < Gtk::StatusIcon
  def initialize
    super
    self.stock = Gtk::Stock::ABOUT
    self.visible = true

    signal_connect("activate") do
      p :open_window
    end

    signal_connect("popup-menu") do
      p :popup_menu
    end
  end
end

si = GrammerApplet.new
Gtk.main
