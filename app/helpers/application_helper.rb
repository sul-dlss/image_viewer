# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  def stacks_url
    if params[:stacks] == 'b'
      Settings.stacks.url_b
    else
      Settings.stacks.url
    end
  end
end
