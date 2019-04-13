require 'json'
require 'redcarpet'
require 'nokogiri'

def lambda_handler(event:, context:)
  md = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  html = Nokogiri::HTML(md.render('hello, **world**'))
  { statusCode: 200, body: JSON.generate(text: html.css('strong').text) }
end
