require 'quimby'
require 'active_support/core_ext'

access_token = params['access_token']
foursquare = Foursquare::Base.new(access_token)
venue = Foursquare::Venue.new(foursquare, params["venue"])

puts venue.photos.map(&:square_300_url).to_json
