
require 'rnotify'
require 'gtk2'
require 'yaml'
require 'rubygems'
require 'oauth/consumer'
require 'json'
require 'monitor'

CONSUMER_KEY = "fxR96GvMXFZ0BdJVIXAUiA"
SECRET = "Zj30K7gePWSYBs2GYv7X9oPsFUaUol2maiDNuj6igTs"
CONSUMER = OAuth::Consumer.new CONSUMER_KEY, SECRET, {:site=>"https://www.yammer.com"}  

# consumer      = OAuth::Consumer.new CONSUMER_KEY, SECRET, {:site=>"https://www.yammer.com"}  
# request_token = consumer.get_request_token
# request_token.authorize_url # go to that url and hit authorize
# access_token  = request_token.get_access_token
# response      = access_token.get '/api/v1/messages.json'
# puts response.body

class Grammer
  REFRESH_WAIT = 30
  NOTIFY_TIMEOUT = 10

  attr_accessor :prefs, :access_token, :request_token, :messages

  def initialize
    Thread.new do 
      loop do
        begin
          sleep REFRESH_WAIT
          @last_top_message_body = last_body
          update_messages
          update_users
          if last_body != @last_top_message_body
            if GrammerWindow.window and GrammerWindow.window.messages_drawn?
              p :window
              Gtk.queue do
                if GrammerWindow.window and GrammerWindow.window.messages_drawn?
                  GrammerWindow.window.draw_messages(@messages)
                end
              end
            else
              p :no_window
              @applet.notify(@messages.last)
            end
          end
        rescue => e
          puts e.message
          puts e.backtrace
        end
      end
    end

    @applet = GrammerApplet.new(self)
    open_window

    if File.exist?(File.expand_path("~/.grammer"))
      @prefs = YAML.load(File.read(File.expand_path("~/.grammer")))
    else
      @prefs = {:users => {}}
    end

    p @prefs
    if @prefs["app_token"] and @prefs["app_secret"]
      @access_token = OAuth::AccessToken.new(CONSUMER, @prefs["app_token"], @prefs["app_secret"])
      update_messages
      update_users
      GrammerWindow.window.draw_messages(@messages)
    else
      GrammerWindow.window.draw_info_form
    end
  end

  def last_body
    return nil unless @messages and @messages.last
    @messages.last["body"]["plain"]
  end

  def update_messages
    response = @access_token.get '/api/v1/messages.json'
    info = JSON.parse(response.body)
    @messages = info["messages"].reverse
  end


  def submit_message(body)
    response = @access_token.post "/api/v1/messages/", :body => body
    draw_messages
  end

  def update_users
    (@messages||[]).each do |message|
      user_info(message["sender_id"])
    end
  end

  def user_info(user_id)
    if user_info = @prefs[:users][user_id]
      user_info
    else
      response = @access_token.get "/api/v1/users/#{user_id}.json"
      info = JSON.parse(response.body)
      @prefs[:users][user_id] = info
      save_prefs
      info
    end
  end

  def open_window
    GrammerWindow.window ||= GrammerWindow.new(self)
    GrammerWindow.window.display
  end

  class GrammerApplet < Gtk::StatusIcon

    def initialize(grammer)
      super()
      @grammer = grammer
      self.stock = ::Gtk::Stock::ABOUT
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
      Notify.init('Autotest') 
      @notification = Notify::Notification.new('X', nil, nil, self)  
    end

    def notify(message)
      @notification.timeout = 1000*NOTIFY_TIMEOUT
      @notification.update(@grammer.user_info(message["sender_id"])["name"], message["body"]["plain"], nil)
      @notification.show
    end
  end

  class GrammerWindow < Gtk::Window
    class << self
      attr_accessor :window
    end

    def initialize(grammer)
      super("Grammer")
      @grammer = grammer
      set_size_request(400, 600)
      signal_connect("destroy") do 
        self.hide_all
        GrammerWindow.window = nil
      end
      show_all
    end

    def messages_drawn?
      @messages_drawn
    end

    def draw_info_form
      self.remove(self.child) if self.child
      vbox = Gtk::VBox.new
      button = Gtk::Button.new("Authorize application")
      button.signal_connect("clicked") do 
        @grammer.request_token = CONSUMER.get_request_token
        fork do
          %x{firefox #{@grammer.request_token.authorize_url}}
        end
        draw_authorized_form
      end
      vbox.pack_start(button)
      add(vbox)
      show_all
    end

    def draw_authorized_form
      self.remove(self.child) if self.child
      button = Gtk::Button.new("AUTHORIZE")
      button.signal_connect("clicked") do
        @grammer.access_token  = @grammer.request_token.get_access_token
        @grammer.prefs["app_token"] = @grammer.access_token.token
        @grammer.prefs["app_secret"] = @grammer.access_token.secret
        @grammer.save_prefs
        draw_messages(@grammer.messages)
      end
      add(button)
      show_all
    end

    def draw_messages(messages)
      self.remove(self.child) if self.child
      vbox = Gtk::VBox.new
      swin = Gtk::ScrolledWindow.new
      swin.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)
      vbox.pack_start(swin)
      messages_vbox = Gtk::VBox.new
      swin.add_with_viewport(messages_vbox)
      messages.each do |message|
        view = Gtk::TextView.new
        text = message["body"]["plain"]
        remaining = text
        new_text = ""
        while remaining and remaining.length > 0
          new_text += remaining[0..50] + "\n"
          remaining = remaining[51..-1]
        end
        new_text += @grammer.user_info(message["sender_id"])["name"] + "  -  " + message["created_at"] + "\n"
        view.buffer.text = new_text
        messages_vbox.pack_end(view)
      end
      hbox = Gtk::HBox.new
      @entry = Gtk::Entry.new
      @submit = Gtk::Button.new("Send")
      @submit.signal_connect("clicked") do
        submit_message(@entry.text)
      end
      hbox.pack_start(@entry)
      hbox.pack_start(@submit)
      vbox.pack_start(hbox, false)
      add(vbox)
      show_all
      @messages_drawn = true
    end

    def save_prefs
      File.open(File.expand_path("~/.grammer"), "w") {|f| f.puts @prefs.to_yaml }
    end
  end
end

module Gtk
  GTK_PENDING_BLOCKS = []
  GTK_PENDING_BLOCKS_LOCK = Monitor.new

  def Gtk.queue &block
    if Thread.current == Thread.main
      block.call
    else
      GTK_PENDING_BLOCKS_LOCK.synchronize do
        GTK_PENDING_BLOCKS << block
      end
    end
  end

  def Gtk.main_with_queue timeout
    Gtk.timeout_add timeout do
      GTK_PENDING_BLOCKS_LOCK.synchronize do
        for block in GTK_PENDING_BLOCKS
          block.call
        end
        GTK_PENDING_BLOCKS.clear
      end
      true
    end
    Gtk.main
  end
end

Grammer.new
Gtk.main_with_queue(100)
