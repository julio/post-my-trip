require 'iron_worker_ng'
require 'quimby'
require 'RMagick'
require 'active_support/core_ext'
require 'cloudfiles'
require 'digest/md5'

File.read("config.sh").split("\n").each do |s|
  matches = s.match(/export (.+)="(.+)"/)
  if !matches.nil?
    captures = matches.captures
    ENV[captures.first] = captures.last
  end
end

class Collage
  def initialize(files, options={})
    @files = files
    @options = options
  end

  def generate(collage_name)
    list = Magick::ImageList.new

    @files.each do |f|
      begin
        image = Magick::Image.read(f)[0]
        list << image
      rescue Magick::ImageMagickError
      end
    end

    orientation = @options["orientation"]
    list = list.montage do |m|
      m.geometry = "300x300"
      if orientation == "landscape"
        m.tile = "6x4"
      else
        m.tile = "4x6"
      end
    end

    list.write(collage_name)
  end
end

access_token = params["access_token"]

client = IronWorkerNG::Client.new(
  :token => ENV["IRON_WORKER_TOKEN"],
  :project_id => ENV["IRON_WORKER_PROJECT_ID"]
)

foursquare = Foursquare::Base.new(access_token)
nearby = foursquare.venues.nearby(:ll => params['latlong'])

tasks = []
nearby.each do |venue|
  tasks << client.tasks.create('GetImage', {
    :access_token => access_token,
    :venue => venue.json
  }).id
end

tasks.each { |id| client.tasks.wait_for(id) }

images = tasks.map do |id|
  log = client.tasks.log(id)
  JSON.parse(log)
end.flatten

# c = Collage.new(images.sample(params['num_rows'].to_i ** 2))
c = Collage.new(images.sample(24), params)
c.generate("collage.jpg")

md5 = Digest::MD5.file("collage.jpg")
filename = "collage-#{md5}.jpg"

cf = CloudFiles::Connection.new(:username => ENV["RACKSPACE_USERNAME"], :api_key => ENV["RACKSPACE_API_KEY"])
container = cf.container('post-my-trip')
container.delete_object(filename) if container.object_exists?(filename)
object = container.create_object(filename)
object.load_from_filename("collage.jpg")

puts [object.public_url].to_json
