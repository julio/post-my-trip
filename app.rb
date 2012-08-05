require 'bundler'
Bundler.require
require 'active_support/core_ext'
require 'open-uri'

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
    :orientation => params['orientation']
  }).id

  { :success => true }.to_json
end

post '/upload' do
  image = RestClient.post "https://snapi.sincerely.com/shiplib/upload",
    :appkey => ENV["SINCERELY_APP_KEY"],
    :photo => open(params['image'])
  image = JSON.parse(image)

  postcard = RestClient.post "https://snapi.sincerely.com/shiplib/create",
    :appkey => ENV["SINCERELY_APP_KEY"],
    :message => "Hello from #eHD",
    :frontPhotoId => image["id"],
    :recipients => [
      {
        :name => params["name"],
        :email => params["email"],
        :street1 => "800 some road",
        :city => "Mountain View",
        :state => "CA",
        :postalcode => "94043",
        :country => "USA"
      }
    ].to_json,
    :sender => {
      :name => "Trae Robrock",
      :email => "trobrock@gmail.com",
      :street1 => "813 Farley St",
      :city => "Mountain View",
      :state => "CA",
      :postalcode => "94043",
      :country => "USA"
    }.to_json

  postcard = JSON.parse(postcard)
  file = RestClient.post "https://snapi.sincerely.com/shiplib/debug",
    :appkey => ENV["SINCERELY_APP_KEY"],
    :printId => postcard["sent_to"].first["printId"]

  content_type "application/pdf"
  attachment "postcard.pdf"
  file
  # File.open("postcard.pdf", "w") do |f|
  #   f.print file
  # end
  # `open postcard.pdf`
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
  redirect @foursquare.authorize_url("http://post-my-trip.herokuapp.com/callback")
end

get '/callback' do
  session[:access_token] = @foursquare.access_token(params["code"], "http://post-my-trip.herokuapp.com/callback")

  redirect '/'
end

def iron_worker
  @iron_worker_client ||= IronWorkerNG::Client.new(
    :token      => ENV["IRON_WORKER_TOKEN"],
    :project_id => ENV["IRON_WORKER_PROJECT_ID"]
  )
end

def foursquare
  if session[:access_token]
    Foursquare::Base.new(session[:access_token])
  else
    Foursquare::Base.new(ENV["FOURSQUARE_KEY"], ENV["FOURSQUARE_SECRET"])
  end
end
