
require 'gtk2'
require 'yaml'
require 'rubygems'
require 'oauth/consumer'
require 'json'

CONSUMER_KEY = "fxR96GvMXFZ0BdJVIXAUiA"
SECRET = "Zj30K7gePWSYBs2GYv7X9oPsFUaUol2maiDNuj6igTs"
CONSUMER = OAuth::Consumer.new CONSUMER_KEY, SECRET, {:site=>"https://www.yammer.com"}  
# consumer      = OAuth::Consumer.new CONSUMER_KEY, SECRET, {:site=>"https://www.yammer.com"}  
# request_token = consumer.get_request_token
# request_token.authorize_url # go to that url and hit authorize
# access_token  = request_token.get_access_token
# response      = access_token.get '/api/v1/messages.json'
# puts response.body

class GrammerApplet < Gtk::StatusIcon
  def initialize
    super
    self.stock = Gtk::Stock::ABOUT
    self.visible = true

    menu = Gtk::Menu.new
    item_open = Gtk::MenuItem.new("Open")
    item_refresh = Gtk::MenuItem.new("Refresh")
    item_quit = Gtk::MenuItem.new("Quit")
    item_open.signal_connect("activate") { open_window }
    item_refresh.signal_connect("activate") do 
      if win = GrammerWindow.window
        win.draw_messages
      end
    end
    item_quit.signal_connect("activate") { Gtk.main_quit }
    menu.append(item_open)
    menu.append(item_refresh)
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
    set_size_request(400, 600)
    signal_connect("destroy") do 
      self.hide_all
      GrammerWindow.window = nil
    end
    
    if File.exist?(File.expand_path("~/.grammer"))
      @prefs = YAML.load(File.read(File.expand_path("~/.grammer")))
    else
      @prefs = {}
    end

    if @prefs["app_token"] and @prefs["app_secret"]
      @access_token = OAuth::AccessToken.new(CONSUMER, @prefs["app_token"], @prefs["app_secret"])
      draw_messages
    else
      draw_info_form
    end

    show_all
  end

  def draw_info_form
    self.remove(self.child) if self.child
    vbox = Gtk::VBox.new
    button = Gtk::Button.new("Authorize application")
    button.signal_connect("clicked") do 
      @request_token = CONSUMER.get_request_token
      fork do
        %x{firefox #{@request_token.authorize_url}}
      end
      draw_authorized_form
    end
    vbox.pack_start(button)
    add(vbox)
  end

  def draw_authorized_form
    self.remove(self.child) if self.child
    button = Gtk::Button.new("AUTHORIZE")
    button.signal_connect("clicked") do
      @access_token  = @request_token.get_access_token
      @prefs["app_token"] = @access_token.token
      @prefs["app_secret"] = @access_token.secret
      save_prefs
      draw_messages
    end
    add(button)
    show_all
  end

  def messages
    response = @access_token.get '/api/v1/messages.json'
    info = JSON.parse(response.body)
    info["messages"].reverse
  end

  def draw_messages
    self.remove(self.child) if self.child
    swin = Gtk::ScrolledWindow.new
    vbox = Gtk::VBox.new
    swin.add_with_viewport(vbox)
    messages.each do |message|
      view = Gtk::TextView.new
      text = message["body"]["plain"]
      remaining = text
      new_text = ""
      while remaining and remaining.length > 0
        new_text += remaining[0..50] + "\n"
        remaining = remaining[51..-1]
      end
      view.buffer.text = new_text
      vbox.pack_end(view)
    end
    add(swin)
    show_all
  end

  def save_prefs
    File.open(File.expand_path("~/.grammer"), "w") {|f| f.puts @prefs.to_yaml }
  end
end

si = GrammerApplet.new
si.open_window
Gtk.main
