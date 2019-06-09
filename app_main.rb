require 'sinatra'
require 'line/bot'
require 'nokogiri'
require 'open-uri'
#以下toho対応用
require 'net/http'
require 'uri'
require 'json'
require 'date'

class Schedule
  attr_accessor :screen, :timetables
  def initialize(screen, timetables)
    @screen = screen; @timetables = timetables
  end
end

class Movie
  attr_accessor :title, :schedules
  def initialize(title)
    @title = title
  end
end

get '/' do
  "Hello world"
  # 動作確認用
  #get_movies_info_text(get_movies_kinezo('http://kinezo.jp/pc/schedule?ush=140feb4'))
  #get_movies_info_text(get_movies_kinezo('http://kinezo.jp/pc/schedule?ush=1703de7'))
  #get_movies_info_text(get_movies_toho('https://hlo.tohotheater.jp/net/schedule/TNPI3050J02.do?__type__=html&__useResultInfo__=no&vg_cd=078&show_day=' + Date.today.strftime("%Y%m%d") + '&term=99'))
end

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

def get_movies_toho(url)
  # jsonなのでパースする
  uri = URI.parse(url)
  json = Net::HTTP.get(uri)
  result = JSON.parse(json)

  # パースしながらmovieを情報を格納
  movies = []
  result[0]["list"][0]["list"].each do |title|
    movie = Movie.new(title["name"])
    schedules = []
    title["list"].each do |screen|
      timetables = []
      screen["list"].each do |time|
        timetables.push(time["showingStart"] + " - " + time["showingEnd"]) if time["showingStart"] != ""
      end
      schedule = Schedule.new(screen["ename"], timetables)
      schedules.push(schedule)
    end
    movie.schedules = schedules
    movies.push(movie)
  end
  movies
end

def get_movies_kinezo(url)

  charset = nil
  html = open(url) do |f|
    charset = f.charset # 文字種を取得
    f.read # htmlを読み込んでhtmlに渡す
  end
  
  # 結果格納用配列
  movies = []
  
  doc = Nokogiri::HTML.parse(html, nil, "utf-8")
  doc.xpath('//div[@class="cinemaTitle elp"]').each do |node|
    # タイトルリストを取得
    title = node.inner_text.split("\n").select{|item| item != ""}.first
    movie = Movie.new(title)
    movies.push(movie)
  end
  
  doc.xpath('//div[@class="theaterListWrap"]').each_with_index do |node, i|
    # スケジュールリストを取得
    schedules = []
    node.xpath('.//table[@class="theaterWrap"]').each do |deep_node|
      timetables = deep_node.inner_text.split("\n").select{|item| item != ""}
      screen = timetables.shift
      schedule = Schedule.new(screen, timetables)
      schedules.push(schedule)
    end
    movies[i].schedules = schedules
  end
  movies
end

def get_movies_info_text(movies)
  reply_text = ''
  movies.each do |movie|
    reply_text << movie.title << "\n"
    movie.schedules.each do |schedule|
      reply_text << schedule.screen << "\n"
      schedule.timetables.each do |timetable|
        reply_text << "\t" << timetable << "\n"
      end
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
        case event.message['text']
        when '映画'
          reply_text = get_movies_info_text(get_movies_kinezo('http://kinezo.jp/pc/schedule?ush=140feb4'))
        when '映画ブルク'
          reply_text = get_movies_info_text(get_movies_kinezo('http://kinezo.jp/pc/schedule?ush=1703de7'))
        when '映画仙台'
          reply_text = get_movies_info_text(get_movies_toho('https://hlo.tohotheater.jp/net/schedule/TNPI3050J02.do?__type__=html&__useResultInfo__=no&vg_cd=078&show_day=' + Date.today.strftime("%Y%m%d") + '&term=99'))
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