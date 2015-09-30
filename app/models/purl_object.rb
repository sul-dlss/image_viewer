require 'nokogiri'

require 'purl/util'
require 'htmlentities'
require 'dor/rights_auth'

class PurlObject
  include Purl::Util

  def self.coder
    @coder ||= HTMLEntities.new
  end

  def coder
    self.class.coder
  end

  def self.attr_deferred(*args)
    args.each do |a|
      define_method a do
        extract_metadata unless @extracted
        instance_variable_get("@#{a}")
      end
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
  alias_method :public_xml, :public_xml_body

  attr_accessor :pid
  attr_deferred :deliverable_files, :downloadable_files, :type

  # Checks if the pair tree directory exists in the document cache for a given druid
  #
  def self.find(id)
    purl = nil
    pair_tree = PurlObject.create_pair_tree(id)

    unless pair_tree.nil?
      file_path = File.join(Settings.document_cache_root, pair_tree)
      purl = PurlObject.new(id) if File.exist?(file_path)
    end

    purl
  end

  # Returns the pair tree directory for a given, valid druid
  #
  def self.create_pair_tree(pid)
    pair_tree = nil

    if pid =~ /^([a-z]{2})(\d{3})([a-z]{2})(\d{4})$/
      pair_tree = File.join(Regexp.last_match(1), Regexp.last_match(2), Regexp.last_match(3), Regexp.last_match(4))
    end

    pair_tree
  end

  # initializes the object with metadata and service streams
  #
  def initialize(id)
    @pid = id
    @extracted     = false
  end

  def extract_metadata
    doc = ng_xml('contentMetadata', 'rightsMetadata')
    doc.encoding = 'UTF-8'

    # Rights metadata
    rights = doc.root.at_xpath('rightsMetadata').to_s
    parsed_rights = Dor::RightsAuth.parse rights

    # Content Metadata
    @type = doc.root.xpath('contentMetadata/@type').to_s

    # File data
    @deliverable_files = []

    # collect all files inside a resource
    doc.root.xpath('contentMetadata/resource').collect do |resource_xml|
      resource_xml.xpath('file').collect do |file|
        resource = Resource.new

        if is_file_ready(file)
          resource.mimetype = file['mimetype']
          resource.size     = file['size']
          resource.shelve   = file['shelve']
          resource.preserve = file['preserve']
          resource.deliver  = file['deliver'] || file['publish']
          resource.filename = file['id']
          resource.objectId = file.parent['objectId']
          resource.type     = file.parent['type'].to_s
          resource.width    = file.at_xpath('imageData/@width').to_s.to_i || 0
          resource.height   = file.at_xpath('imageData/@height').to_s.to_i || 0

          resource.rights_world, resource.rights_world_rule = parsed_rights.world_rights_for_file(resource.filename)
          resource.rights_stanford, resource.rights_stanford_rule = parsed_rights.stanford_only_rights_for_file(resource.filename)

          if resource.width > 0 && resource.height > 0
            resource.levels = ((Math.log([resource.width, resource.height].max) / Math.log(2)) - (Math.log(96) / Math.log(2))).ceil + 1
          end

          resource.imagesvc = file.at_xpath('location[@type="imagesvc"]/text()').to_s
          resource.url      = file.at_xpath('location[@type="url"]/text()').to_s
        end

        if !resource_xml.at_xpath('attr[@name="label"]/text()').nil?
          resource.description_label = resource_xml.at_xpath('attr[@name="label"]/text()').to_s
        elsif !resource_xml.at_xpath('label/text()').nil?
          resource.description_label = resource_xml.at_xpath('label/text()').to_s
        end

        resource.sequence = resource_xml['sequence'].to_s || 0

        # if the resource has a deliverable file or at least one sub_resource, add it to the array
        unless resource.nil?
          if resource.type != 'object'
            @deliverable_files.push(resource)
          else
            @downloadable_files.push(resource)
          end
        end
      end
    end

    # collect all resources and files inside a resource
    doc.root.xpath('contentMetadata/resource').collect do |resource_xml|
      resource = Resource.new
      resource.sequence = resource_xml['sequence'].to_s || 0

      resource.sub_resources = resource_xml.xpath('resource').collect do |sub_resource_xml|
        sub_file = sub_resource_xml.at_xpath('file')
        sub_resource = Resource.new

        if is_file_ready(sub_file)
          sub_resource.mimetype = sub_file['mimetype']
          sub_resource.size     = sub_file['size']
          sub_resource.shelve   = sub_file['shelve']
          sub_resource.preserve = sub_file['preserve']
          sub_resource.deliver  = sub_file['deliver'] || file['publish']
          sub_resource.filename = sub_file['id']
          sub_resource.objectId = sub_file.parent['objectId']
          sub_resource.type     = sub_file.parent['type']
          sub_resource.width    = sub_file.at_xpath('imageData/@width').to_s.to_i || 0
          sub_resource.height   = sub_file.at_xpath('imageData/@height').to_s.to_i || 0

          sub_resource.rights_world, sub_resource.rights_world_rule = parsed_rights.world_rights_for_file(sub_resource.filename)
          sub_resource.rights_stanford, sub_resource.rights_stanford_rule = parsed_rights.stanford_only_rights_for_file(sub_resource.filename)

          if sub_resource.width > 0 && sub_resource.height > 0
            sub_resource.levels   = ((Math.log([sub_resource.width, sub_resource.height].max) / Math.log(2)) - (Math.log(96) / Math.log(2))).ceil + 1
          end

          sub_resource.imagesvc = sub_file.at_xpath('location[@type="imagesvc"]/text()').to_s
          sub_resource.url      = sub_file.at_xpath('location[@type="url"]/text()').to_s
        end

        if !sub_resource_xml.at_xpath('attr[@name="label"]/text()').nil?
          sub_resource.description_label = sub_resource_xml.at_xpath('attr[@name="label"]/text()').to_s
        elsif !sub_resource_xml.at_xpath('label/text()').nil?
          sub_resource.description_label = sub_resource_xml.at_xpath('label/text()').to_s
        end

        sub_resource.sequence = sub_resource_xml['sequence'].to_s || 0

        sub_resource
      end

      # if the resource has a deliverable file or at least one sub_resource, add it to the array
      if (!resource.nil? && !resource.filename.nil?) || resource.sub_resources.length > 0
        if resource.type != 'object'
          @deliverable_files.push(resource)
        else
          @downloadable_files.push(resource)
        end
      end
    end

    # Rights Metadata
    rights = doc.root.at_xpath('rightsMetadata')
    unless rights.nil?
      read = rights.at_xpath('access[@type="read"]/machine/*')

      unless read.nil?
        @read_group = read.name == 'group' ? read.text : read.name
      end

      @embargo_release_date = rights.at_xpath('.//embargoReleaseDate/text()').to_s

      if  !@embargo_release_date.nil? && @embargo_release_date != ''
        embargo_date_time = Time.parse(@embargo_release_date)
        @embargo_release_date = '' unless embargo_date_time.future?
      end

      @copyright_stmt = rights.at_xpath('copyright/human/text()').to_s
      @use_and_reproduction_stmt = rights.at_xpath('use/human[@type="useAndReproduction"]/text()').to_s
      @cclicense_symbol = rights.at_xpath('use/machine[@type="creativeCommons"]/text()').to_s

      if @cclicense_symbol.blank?
        @cclicense_symbol = rights.at_xpath('use/machine[@type="creativecommons"]/text()').to_s
      end

      @odc_license = rights.at_xpath('use/machine[@type="opendatacommons"]/text()').to_s

      if @odc_license.blank?
        @odc_license = rights.at_xpath('use/machine[@type="openDataCommons"]/text()').to_s
      end

      if @odc_type.blank?
        @odc_type = rights.at_xpath('use/human[@type="openDataCommons"]/text()').to_s
      end

    end

    @extracted = true
  end

  def ready?
    return true unless @public_xml.blank? || @public_xml == '<public/>'
    false
  end
  alias_method :is_ready?, :ready?

  # check if this object is of type image
  def image?
    return true if !type.nil? && type =~ /Image|Map|webarchive-seed/i

    false
  end
  alias_method :is_image?, :image?

  private

  # retrieve the given document from the document cache for the given object identifier
  def get_metadata(doc_name)
    start_time = Time.now
    pair_tree = PurlObject.create_pair_tree(@pid)
    contents = "<#{doc_name}/>"
    unless pair_tree.nil?
      file_path = File.join(Settings.document_cache_root, pair_tree, doc_name)
      contents = File.read(file_path) if File.exist?(file_path)

      if !Rails.env == 'production'
        contents.gsub!('stacks.stanford.edu', 'stacks-test.stanford.edu')
      end
    end
    total_time = Time.now - start_time
    Rails.logger.warn "Completed get_metadata for #{@pid} fetching #{doc_name} in #{total_time}"
    contents
  end

  def attributes
    { druid: pid }
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
        Hurley.get(url_or_path)
      else
        DocumentCacheResource.new(url_or_path)
      end
    end
  end

  def ng_xml(*streams)
    if @ng_xml.nil?
      content = @public_xml

      if content.nil? || content.strip.empty?
        content = "<publicObject objectId='#{@pid}'/>"
      end

      @ng_xml = Nokogiri::XML(content)

      streams.each do |doc_name|
        if @ng_xml.root.at_xpath(%{*[local-name() = "#{doc_name}"]}).nil?
          stream_content = get_metadata(doc_name)
          unless stream_content.empty?
            @ng_xml.root.add_child(Nokogiri::XML(stream_content).root)
          end
        end
      end
    end
    @ng_xml
  end
end
