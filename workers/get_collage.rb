require 'iron_worker_ng'
require 'quimby'
require 'RMagick'
require 'active_support/core_ext'
require 'cloudfiles'
require 'digest/md5'

CONFIG = YAML.load_file('config.yml')

class Collage
  def initialize(files)
    @files = files
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

    list = list.montage do |m|
      m.geometry = "100x100"
    end

    list.write(collage_name)
  end
end

access_token = params["access_token"]

client = IronWorkerNG::Client.new(
  :token => CONFIG["iron_worker"]["token"],
  :project_id => CONFIG["iron_worker"]["project_id"]
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

c = Collage.new(images.sample(params['num_rows'].to_i ** 2))
c.generate("collage.jpg")

md5 = Digest::MD5.file("collage.jpg")
filename = "collage-#{md5}.jpg"

cf = CloudFiles::Connection.new(:username => CONFIG["rackspace"]["username"], :api_key => CONFIG["rackspace"]["api_key"])
container = cf.container('post-my-trip')
container.delete_object(filename) if container.object_exists?(filename)
object = container.create_object(filename)
object.load_from_filename("collage.jpg")

puts [object.public_url].to_json
