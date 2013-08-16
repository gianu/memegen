require 'hipchat'
require 'aws/s3'

class MemeGenerator
  class Hipchat
    MEMEGEN_PATH = File.expand_path("~/.memegen")
    CONFIG_PATH  = File.join(MEMEGEN_PATH, ".hipchat")

    class << self
      def config
        return unless File.exists?(CONFIG_PATH)
        @config ||= read_config
      end

      def prompt_config
        require 'readline'
        puts "Set your hipchat (and amazon s3) credentials..." unless config

        hipchat_api_token = Readline.readline("Hipchat Api Token: ").strip
        username = Readline.readline("Hipchat username: ").strip
        amazon_access_key_id = Readline.readline("Amazon Access key id: ").strip
        amazon_access_key_secret = Readline.readline("Amazon Access key secret: ").strip
        amazon_bucket = Readline.readline("Amazon bucket: ").strip

        write_config([hipchat_api_token, username, amazon_access_key_id, amazon_access_key_secret, amazon_bucket])

        puts "Config saved successfully!"
      end

      def upload(hipchat_channel, path)
        prompt_config unless config

        puts "Uploading to Amazon S3 - bucket #{config[:amazon_bucket]}"
        AWS::S3::Base.establish_connection!(
          access_key_id: config[:amazon_access_key],
          secret_access_key: config[:amazon_access_key_secret]
        )

        file_name = path.split("/").last
        file_name_on_amazon = "/meme/#{file_name}"
        AWS::S3::S3Object.store(file_name_on_amazon, open(path), config[:amazon_bucket])
        url = AWS::S3::S3Object.url_for(file_name_on_amazon, config[:amazon_bucket], use_ssl: true)

        puts "Posting message to hipchat (channel: #{hipchat_channel})"

        silence_stream(STDERR) do
          begin
            client = HipChat::Client.new(config[:hipchat_api_token])
            client[hipchat_channel].send(config[:hipchat_username], url, message_format: 'text')
          rescue HipChat::Unauthorized
            puts "Your hipchat credentials are incorrect. Please enter them again."
            prompt_config
            upload(path)
          rescue HipChat::UnknownRoom
            puts "Unknown room."
          end
        end

        puts "Done!"
      end

      private

      def silence_stream(stream)
        old_stream = stream.dup
        stream.reopen(RbConfig::CONFIG['host_os'] =~ /mswin|mingw/ ? 'NUL:' : '/dev/null')
        stream.sync = true
        yield
      ensure
        stream.reopen(old_stream)
      end

      def read_config
        data = File.read(CONFIG_PATH)
        values = data.split("|")
        {
          hipchat_api_token: values[0].strip,
          hipchat_username: values[1].strip,
          amazon_access_key: values[2].strip,
          amazon_access_key_secret: values[3].strip,
          amazon_bucket: values[4].strip
        }
      end

      def write_config(config)
        FileUtils.mkdir_p(MEMEGEN_PATH)
        File.open(CONFIG_PATH, "w") do |file|
          file.write(config.join("|"))
        end
      end
    end
  end
end
