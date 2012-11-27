(function( $ ){
  var serverUrls = {
    'test': 'http://purl-test.stanford.edu',
    'prod': 'http://purl-prod.stanford.edu',
    'local': 'http://localhost:3000'
  }

  $.fn.embedPurl = function(server, druid, sequence, size) {
    var serverURL = serverUrls[server];
    var $this = $(this);

    $.ajax({
      type: "GET",
      url: serverURL + '/' + druid + '/embed-js',
      contentType: "text/html; charset=utf-8",
      data: { peContainerWidth: $this.width() , peContainerHeight: $this.height() },
      dataType: "html",

      success: function(html) {
        $.each(['purl_embed', 'zpr'], function(index, value) {
          $('head').append('<link rel="stylesheet" href="' + serverURL + '/stylesheets/' + value + '.css" type="text/css" />')
        });

        $.getScript(serverURL + '/javascripts/zpr.js', function() { });
        $.getScript(serverURL + '/javascripts/cselect.js', function() { });

        $.getScript(serverURL + '/javascripts/purl_embed.js', function() {
          $this.html(html);
          var pe = new purlEmbed(peImgInfo, pePid, peStacksURL, sequence, size);
        });
      },
      error: function() {
        $this.html("Error loading images for " + druid);
      }
    });
  };
})(jQuery);