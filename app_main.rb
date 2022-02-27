require 'sinatra'
require 'sinatra/reloader'
require 'line/bot'
require 'nokogiri'
require 'open-uri'
#以下toho対応用
require 'net/http'
require 'uri'
require 'json'
require 'date'

class Movie
  attr_accessor :title, :schedules
  def initialize(title)
    @title = title
  end
end

keyword_urls = {
  '映画' => 'https://tjoy.jp/shinjuku_wald9',
  '映画ブルク' => 'https://tjoy.jp/yokohama_burg13'
}

get '/' do
  "Hello world"
  # 動作確認用
  # url = keyword_urls['映画']
  # get_movies_info_text(get_movies_kinezo(url))
end

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

def get_movies_kinezo(url)
  opened_url= URI.open(url)
  doc = Nokogiri::HTML(opened_url)

  movies = doc.at_css('div.box-film-wapper')
              .css('section.section-container')
              .map do |section|
                title = section.at_css('h5.js-title-film').text.strip
                movie = Movie.new(title)
                movie.schedules = section.css('p.schedule-time').map{ |time| time.text.strip }
                movie
              end
  movies
end

def get_movies_info_text(movies)
  reply_text = ''
  movies.each do |movie|
    reply_text << movie.title << "\n"
    movie.schedules.each do |schedule|
      reply_text << "\t" << schedule << "\n"
    end
    reply_text << "\n"
  end
  reply_text
end

post '/callback' do
  body = request.body.read

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    error 400 do 'Bad Request' end
  end

  events = client.parse_events_from(body)
  events.each { |event|
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        reply_text = event.message['text']
        text = event.message['text']
        url = keyword_urls[text]
        unless url.nil?
          reply_text = get_movies_info_text(get_movies_kinezo(url))
        end
        message = {
          type: 'text',
          text: reply_text
        }
        client.reply_message(event['replyToken'], message)
      when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
        response = client.get_message_content(event.message['id'])
        tf = Tempfile.open("content")
        tf.write(response.body)
      end
    end
  }

  "OK"
end