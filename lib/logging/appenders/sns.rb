require 'aws'
require 'json'
require 'net/http'

module Logging::Appenders

  # Accessor / Factory for the SNS appender.
  #
  def self.sns( *args )
    return ::Logging::Appenders::SNS if args.empty?
    ::Logging::Appenders::SNS.new(*args)
  end

  # Provides an appender that can send log messages via Amazon's Simple Notification System
  #
  class SNS < ::Logging::Appender
    include Buffering

    attr_reader :aws_access_id, :aws_secret_key
    attr_accessor :sms_method, :pastebin_developer_key
    attr_accessor :extra_json, :human_readable_header, :human_readable_footer
    attr_accessor :subject, :sns_topic

    # call-seq:
    #    SNS.new( name, :aws_access_id => '...', :aws_secret_key => '...',
    #             :sns_topic => 'arn:aws:sns:us-east-1:054794666397:MyTopic',
    #             :subject => 'Server Alert!',
    #             :sms_method => :pastebin, :pastebin_developer_key => '...',
    #             :extra_json => {:app_name => "my_app", :host => "#{%x(uname -n).strip}"},
    #             :human_readable_header => 'The following errors occurred: ',
    #             :human_readable_footer => 'kthxbye!')
    #
    # Create a new SNS appender that will buffer messages and then send them out in batches to the
    # AWS SNS Topic. See the options below to configure how messages are published to the topic
    # of choice. All the buffering options apply to the SNS appender.
    #
    # The following options are required:
    #
    #  :aws_access_id  - The AWS Access ID of the IAM User account configured to be able to publish to sns_topic
    #  :aws_secret_key - The AWS Secret Key of the IAM User account configured to be able to publish to sns_topic
    #  :sns_topic - The ARN of the AWS SNS Topic that you wish to publish messages to.
    #
    # The following options are optional:
    #
    #  :subject               - The subject line for any email endpoints.
    #  :sms_method - When sending a message to an SMS endpoint you have two options:
    #      :truncate - If the message is longer than 140 characters the SMS is simply truncated.
    #      :pastebin - If the message is longer than 140 characters create an entry on pastebin.com
    #                  with the full message contents.  An SMS message is sent with the pastebin URL
    #                  giving the recipient the ability to go straight to the full message at
    #                  pastebin.com from their mobile device.  To use this option you must create a
    #                  (free) account at pastebin.com and then provide your developer key in the
    #                  :pastebin_developer_key option.
    #  :pastebin_developer_key - If you wish to use :pastebin for the :sms_method option then you
    #      must supply a developer key here.  You can get a developer key by opening a free account
    #      at pastebin.com and then going here: http://pastebin.com/api#1 .  Just copy/paste your
    #      developer key into this option.
    #  :extra_json - When sending to non-human endpoints (this means "HTTP", "HTTPS", "email
    #      (json)", and "SQS") a JSON document is given the provides the endpoint the ability to get
    #      useful metadata.  You can append additional JSON to this document for your program
    #      endpoints to consume with this option.  Must be a ruby hash, array, string, integer, or
    #      nil.  The value you pass here will be encoded as JSON by the appender.
    #  :human_readable_header - Text that is prepended to messages sent to human readable endpoints
    #      ("email" and "SMS").
    #  :human_readable_footer - Text that is appended to messages sent to human readable endpoints
    #      ("email" and "SMS").
    #
    # Example:
    #
    # Setup an SNS appender that will buffer messages for up to 1 minute,
    # and only send messages for ERROR and FATAL messages. This example uses
    # a fake SNS Topic and fake IAM credentials.
    #
    #   Logger.appenders.sns( 'critical_sns',
    #       :aws_access_id          => "AKWQWH53XIEJH5SMBLIQN",
    #       :aws_secret_key         => "JdD+kdjls/diwJDLSKJ3kD9lwkjej3BBiiDJtb882jJAQWD",
    #       :sns_topic              => "arn:aws:sns:us-east-1:054794666397:MyTopic",
    #       :subject                => "Application Errors [#{%x(uname -n).strip}]",
    #       :sms_method             => :pastebin,
    #       :pastebin_developer_key => 'abcdef0123456789abcdef0123456789',
    #       :extra_json             => {:app_name => "my_app", :host => "#{%x(uname -n).strip}"},
    #       :human_readable_header  => "Some errors occurred!",
    #       :human_readable_footer  => "Please open a ticket and contact the developers at 555-555-5555",
    #
    #       :auto_flushing => 200,     # send an email after 200 messages have been buffered
    #       :flush_period  => 60,      # send an email after one minute
    #       :level         => :error   # only process log events that are "error" or "fatal"
    #   )
    #
    def initialize( name, opts = {} )
      opts[:header] = false
      super(name, opts)

      af = opts.getopt(:buffsize) ||
           opts.getopt(:buffer_size) ||
           100
      configure_buffering({:auto_flushing => af}.merge(opts))

      # get parameters
      self.aws_access_id = opts.getopt :aws_access_id
      raise ArgumentError, 'Must specify aws_access_id' if @aws_access_id.nil? || @aws_access_id.empty?
      self.aws_secret_key = opts.getopt :aws_secret_key
      raise ArgumentError, 'Must specify aws_secret_key' if @aws_secret_key.nil? || @aws_secret_key.empty?
      self.sns_topic = opts.getopt :sns_topic
      raise ArgumentError, 'Must specify sns_topic' if @sns_topic.nil? || @sns_topic.empty?
      self.subject    = opts.getopt :subject, "Message from #{$0}"
      self.sms_method = opts.getopt(:sms_method, :truncate)
      raise ArgumentError, 'sms_method must be :truncate or :pastebin' unless [:truncate, :pastebin].include?(@sms_method)
      self.pastebin_developer_key = opts.getopt(:pastebin_developer_key)
      raise ArgumentError, 'Must specify :pastebin_developer_key when sms_method is :pastebin' if @sms_method == :pastebin && (@pastebin_developer_key.nil? || @pastebin_developer_key.empty?)
      self.extra_json = opts.getopt(:extra_json)
      self.human_readable_header = opts.getopt(:human_readable_header)
      self.human_readable_footer = opts.getopt(:human_readable_footer)
    end

    # Close the appender. If the layout contains a foot, it will not be sent.  Note that the layout
    # footer is different from the human_readable_footer
    def close( *args )
      super(false)
    end

  private

    # This method is called by the buffering code when messages need to be
    # sent out as an SNS message to a topic.
    def canonical_write( str )

      # We want two message types: machine readable (json) and human readable.
      human = "%s%s%s" % [@human_readable_header, str, @human_readable_footer]
      machine = {:extra_json => @extra_json, :message => str}.to_json

      sms_message = str # Default is for Amazon to truncate this for us.
      if @sms_method == :pastebin
        # Go here to learn more: http://pastebin.com/api
        uri = URI("http://pastebin.com/api/api_post.php")
        params = {
          "api_option" => "paste",
          "api_paste_private" => 1, # 0=public, 1=unlisted, 2=private
          "api_paste_name" => @subject,
          "api_paste_expire_date" => "1D", # 10M (10 min), 1H (1 Hour), 1D (1 day), 1M (1 month), N (never)
          "api_paste_format" => "text",
          "api_dev_key" => @pastebin_developer_key,
          "api_paste_code" => human
        }
        begin
          pastebin_result = Net::HTTP.post_form(uri, params)
        rescue Exception => msg
          ::Logging.log_internal {'Error posting to pastebin.com.  Falling back to :truncate behavior instead'}
          ::Logging.log_internal(-2) { msg }
        else
          if match_data = %r[^Bad API request, (.*)$].match(pastebin_result.body)
            ::Logging.log_internal {'Got error msg from pastebin.com.  Falling back to :truncate behavior instead'}
            ::Logging.log_internal(-2) { match_data[1] }
          else
            paste_id = pastebin_result.body.strip.split("/")[-1]
            # Amazon prepends topic display name and '>' char to SMS message.  So the following will
            # look something like this on mobile device:
            # MYTOPIC> New msg at http://pastebin.com/raw.php?i=Ujd93ji32
            sms_message = " New msg at http://pastebin.com/raw.php?i=#{paste_id}"
          end
        end
      end

      ### construct message options
      publish_options = {
        :subject => @subject, # Subject only for email endpoints
        :email => human,
        # For some reason the :sms option isn't yet supported by the AWS Ruby SDK.  Instead the AWS
        # Ruby SDK uses the default_message parameter for SMS content. I think this is a bug and
        # will probably be fixed in the future.  I'm providing the :sms key here to future-proof ;)
        :sms => sms_message,
        :http => machine,
        :https => machine,
        :email_json => machine,
        :sqs => machine
      }

      ### send message
      sns = AWS::SNS.new(:aws_access_id => @aws_access_id, :aws_secret_key => @aws_secret_key)
      sns.topics[@sns_topic].publish(sms_message, publish_options)
      self
    rescue Exception => err
      self.level = :off
      ::Logging.log_internal {'SNS notifications have been disabled'}
      ::Logging.log_internal(-2) {err}
    end

  end   # SNS
end   # Logging::Appenders
