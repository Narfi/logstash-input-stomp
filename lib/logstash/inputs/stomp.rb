# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require 'pp'

class LogStash::Inputs::Stomp < LogStash::Inputs::Base
  attr_accessor :client

  config_name "stomp"

  default :codec, "plain"

  # The address of the STOMP server.
  config :host, :validate => :string, :default => "localhost", :required => true

  # The port to connet to on your STOMP server.
  config :port, :validate => :number, :default => 61613

  # The username to authenticate with.
  config :user, :validate => :string, :default => ""

  # The password to authenticate with.
  config :password, :validate => :password, :default => ""

  # The destination to read events from.
  #
  # Example: `/topic/logstash`
  config :destination, :validate => :string, :required => true

  # The vhost to use
  config :vhost, :validate => :string, :default => nil

  # Include message headers
  config :headers, :validate => :boolean, :default => false
  
  # Header array
  config :header_array, :validate => :array, :default => []
  
  # Enable debugging output?
  config :debug, :validate => :boolean, :default => false

  private
  def connect
    begin
      @client.connect
      @logger.debug? && @logger.debug("Connected to stomp server") if @client.connected?
    rescue OnStomp::ConnectFailedError, OnStomp::UnsupportedProtocolVersionError=> e
      @logger.warn("Failed to connect to stomp server, will retry", :exception => e, :backtrace => e.backtrace)
      if stop?
        sleep 2
        retry
      end
    end
  end

  public
  def register
    require "onstomp"
    @client = new_client
    @client.host = @vhost if @vhost
    @stomp_url = "stomp://#{@user}:#{@password}@#{@host}:#{@port}/#{@destination}"

    # Handle disconnects
    @client.on_connection_closed {
      connect
      subscription_handler # is required for re-subscribing to the destination
    }
    connect
  end # def register

  def new_client
    OnStomp::Client.new("stomp://#{@host}:#{@port}", :login => @user, :passcode => @password.value)
  end

  private
  def subscription_handler
    @client.subscribe(@destination) do |msg|
	@codec.decode(msg.body) do |event|
		decorate(event)
		add_headers(event, msg) if @headers
		@output_queue << event
      end
    end
    #In the event that there is only Stomp input plugin instances
    #the process ends prematurely. The above code runs, and return
    #the flow control to the 'run' method below. After that, the
    #method "run_input" from agent.rb marks 'done' as 'true' and calls
    #'finish' over the Stomp plugin instance.
    #'Sleeping' the plugin leaves the instance alive.
    until stop?
      sleep 1
    end
  end

  public
  def run(output_queue)
    @output_queue = output_queue
    subscription_handler
  end # def run
  
  private
  def add_headers(event, msg)
	@header_array.empty? ? add_all_headers(event, msg) : add_specific_headers(event, msg)
  end
  
  private
  def add_all_headers(event, msg)
	msg.headers.each do |key, value|
		event[key] = value
	end
  end
  
  private
  def add_specific_headers(event, msg)
	#Convert Stomp Frame Header to Ruby hash
	header_hash = {}
	msg.headers.each do |key, value|
		header_hash[key] = value
	end
	
	#Find specific headers
	@header_array.each do |key|
		event[key] = header_hash[key] if header_hash.key?(key)
	end
  end
end # class LogStash::Inputs::Stomp
