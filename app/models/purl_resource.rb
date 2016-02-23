require 'dor/util'

class PurlResource
  include ActiveModel::Model
  attr_accessor :id
  alias_method :druid, :id

  class DruidNotValid < StandardError; end
  class ObjectNotReady < StandardError; end

  def self.find(id)
    fail DruidNotValid, id unless Dor::Util.validate_druid(id)

    PurlResource.new(id: id).tap do |obj|
      fail ObjectNotReady, id unless obj.ready?
    end
  end

  # rubocop:disable Metrics/MethodLength, Style/PredicateName
  def self.has_resource(options)
    options.each do |key, value|
      define_method "#{key}_resource" do
        response_cache[key] ||= cache_resource(key) do
          fetch_resource(value)
        end
      end

      define_method "#{key}_body" do
        send("#{key}_resource").body if send("#{key}_resource").success?
      end

      define_method "#{key}?" do
        send("#{key}_body").present?
      end
    end
  end
  # rubocop:enable Metrics/MethodLength, Style/PredicateName

  has_resource public_xml: Settings.purl_resource.public_xml

  def ready?
    public_xml?
  end

  def public_xml_document
    @public_xml_document ||= Nokogiri::XML(public_xml_body)
  end

  def public_xml
    @public_xml ||= PublicXml.new(public_xml_document)
  end

  delegate :rights_metadata, to: :public_xml

  def content_metadata
    @content_metadata ||= ContentMetadata.new(public_xml.content_metadata)
  end

  def rights
    @rights ||= RightsMetadata.new(rights_metadata)
  end

  def type
    @type ||= content_metadata.type
  end

  def image?
    !type.nil? && type =~ /Image|Map|webarchive-seed/i
  end

  concerning :Caching do
    def cache_key
      "purl_resource/druid:#{id}"
    end

    def updated_at
      if public_xml_resource.respond_to? :updated_at
        public_xml_resource.updated_at
      elsif public_xml_resource.respond_to?(:header) && public_xml_resource.header[:last_modified].present?
        public_xml_resource.header[:last_modified]
      else
        Time.zone.now
      end
    end
  end

  concerning :ActiveModelness do
    def attributes
      { druid: id, druid_tree: druid_tree }
    end

    def persisted?
      true
    end

    private

    def druid_tree
      Dor::Util.create_pair_tree(druid) || druid
    end
  end

  concerning :Fetching do
    def cache_resource(key, &block)
      if Settings.resource_cache.enabled
        Rails.cache.fetch("#{cache_key}/#{key}", expires_in: Settings.resource_cache.lifetime, &block)
      else
        yield
      end
    end

    def response_cache
      @response_cache ||= {}
    end

    def fetch_resource(value)
      url_or_path = value % attributes

      case url_or_path
      when /^http/
        Faraday.get(url_or_path)
      else
        DocumentCacheResource.new(url_or_path)
      end
    end
  end
end
