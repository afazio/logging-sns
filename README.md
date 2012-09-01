# Logging::Appenders::SNS

AWS Simple Notification Service (SNS) appender for Logging.

## Installation

Add this line to your application's Gemfile:

    gem 'logging-sns'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install logging-sns

## Usage

Here is an example.

    require 'logging'
    require 'logging-sns'
    
    class CriticalCode
      def initialize
        @logger = Logging.logger[self]
        options = {
          :access_key_id => "...", :secret_access_key => "...",
          :sns_topic => "arn:aws:sns:us-east-1:723967856371:Server-Alerts",
          :subject => "A critical error has occurred!", :level => :error,
          :sms_method => :pastebin, :pastebin_developer_key => '7b56e9d960c289bf698aaa66df647e529',
          :human_readable_header => "Bad news, boys. Things are going very very wrong.\n",
          :human_readable_footer => "In case of continuing issues, please unplug the data center and plug it back in."
        }
        @logger.add_appenders(Logging.appenders.sns('critical', options))
      end

      def check_something_important
        @logger.error "The server will explode in 15 minutes!"
        @logger.fatal "AAAAAAAAGGGHGGHHGHHGHGH!!!"
      end
    end
    

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
