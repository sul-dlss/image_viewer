require 'uri'
require 'purl/util'

module PurlHelper
  def get_image_json_array
    Purl::Util.get_image_json_array(@purl)
  end

  def purl_url(druid = nil)
    druid ||= @purl.druid

    Settings.purl.url + '/' + @purl.druid
  end
end
