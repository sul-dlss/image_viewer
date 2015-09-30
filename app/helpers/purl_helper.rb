require 'uri'
require 'purl/util'

module PurlHelper
  def get_image_json_array
    Purl::Util.get_image_json_array(@purl.deliverable_files)
  end
end
