module ImgEmbedHtmlHelper
  def imgEmbedHtml
    page = [
      '<div class="pe-container">'
    ]
    with_format('html') do
      page << render_to_string(partial: 'embed/img_viewer')
    end
    page.concat([
      '</div>'
    ])

    {
      page: page.join(''),
      peStacksURL: Settings.stacks.url,
      pePid: @purl.druid,
      peImgInfo: get_image_json_array
    }
  end

  def with_format(format, &block)
    old_formats = formats
    self.formats = [format]
    block.call
    self.formats = old_formats
    nil
  end
end
