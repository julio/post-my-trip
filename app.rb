require 'bundler'
Bundler.require
require 'active_support/core_ext'

CONFIG = YAML.load_file(File.join(File.dirname(__FILE__), 'config.yml'))

enable :sessions

before do
  @foursquare = foursquare

  redirect '/auth' unless request.path_info =~ /\/auth/ ||
                          request.path_info =~ /\/callback/ ||
                          session[:access_token]
end

get '/' do
  erb :index
end

post '/create' do
  client = iron_worker

  session[:tasks] = []
  session[:tasks] << client.tasks.create("GetCollage", {
    :access_token => session[:access_token],
    :latlong => params['latlong'],
    :num_rows => params['num_rows']
  }).id

  { :success => true }.to_json
end

get '/collage' do
  return nil if session[:tasks].blank?

  client = iron_worker

  images = []
  session[:tasks].each_with_index do |id, i|
    if client.tasks.get(id).status == "complete"
      log = client.tasks.log(id).chomp
      images.concat JSON.parse(log)
      session[:tasks].delete_at(i)
    end
  end

  images.reject!(&:blank?)

  images.to_json
end

get '/auth' do
  redirect @foursquare.authorize_url("http://0.0.0.0:4567/callback")
end

get '/callback' do
  session[:access_token] = @foursquare.access_token(params["code"], "http://0.0.0.0:4567/callback")

  redirect '/'
end

def iron_worker
  @iron_worker_client ||= IronWorkerNG::Client.new(
    :token      => CONFIG["iron_worker"]["token"],
    :project_id => CONFIG["iron_worker"]["project_id"]
  )
end

def foursquare
  if session[:access_token]
    Foursquare::Base.new(session[:access_token])
  else
    Foursquare::Base.new(CONFIG["foursquare"]["key"], CONFIG["foursquare"]["secret"])
  end
end