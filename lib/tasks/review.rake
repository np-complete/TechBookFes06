# Copyright (c) 2006-2018 Minero Aoki, Kenshi Muto, Masayoshi Takahashi, Masanori Kado.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'fileutils'
require 'rake/clean'
require 'yaml'

BOOK = ENV['REVIEW_BOOK'] || 'book'
BOOK_PDF = BOOK + '.pdf'
BOOK_EPUB = BOOK + '.epub'
CONFIG_FILE = ENV['REVIEW_CONFIG_FILE'] || 'config.yml'
CATALOG_FILE = ENV['REVIEW_CATALOG_FILE'] || 'catalog.yml'
WEBROOT = ENV['REVIEW_WEBROOT'] || 'webroot'
TEXTROOT = BOOK + '-text'
TOPROOT = BOOK + '-text'

def build(mode, chapter)
  sh "review-compile --target=#{mode} --footnotetext --stylesheet=style.css #{chapter} > tmp"
  mode_ext = { 'html' => 'html', 'latex' => 'tex', 'idgxml' => 'xml', 'top' => 'txt', 'plaintext' => 'txt' }
  FileUtils.mv 'tmp', chapter.gsub(/re\z/, mode_ext[mode])
end

def build_all(mode)
  sh "review-compile --target=#{mode} --footnotetext --stylesheet=style.css"
end

task default: :html_all

desc 'build html (Usage: rake build re=target.re)'
task :html do
  if ENV['re'].nil?
    puts 'Usage: rake build re=target.re'
    exit
  end
  build('html', ENV['re'])
end

desc 'build all html'
task :html_all do
  build_all('html')
end

desc 'preproc all'
task :preproc do
  Dir.glob('*.re').each do |file|
    sh "review-preproc --replace #{file}"
  end
end

desc 'generate PDF and EPUB file'
task all: %i[pdf epub]

desc 'generate PDF file'
task pdf: BOOK_PDF

desc 'generate static HTML file for web'
task web: WEBROOT

desc 'generate text file (without decoration)'
task plaintext: TEXTROOT do
  sh "review-textmaker -n #{CONFIG_FILE}"
end

desc 'generate (decorated) text file'
task text: TOPROOT do
  sh "review-textmaker #{CONFIG_FILE}"
end

desc 'generate EPUB file'
task epub: BOOK_EPUB

IMAGES = FileList['images/**/*']
OTHERS = ENV['REVIEW_DEPS'] || []
SRC = FileList['*.md']
OBJ = SRC.ext('re')
INPUT = OBJ + [CONFIG_FILE, CATALOG_FILE]
SRC_EPUB = FileList['*.css']
SRC_PDF = FileList['layouts/*.erb', 'sty/**/*.sty']

rule '.re' => '.md' do |t|
  sh "bundle exec md2review --render-link-in-footnote #{t.source} > #{t.name}"
end

file BOOK_PDF => INPUT do
  FileUtils.rm_rf [BOOK_PDF, BOOK, BOOK + '-pdf']
  sh "review-pdfmaker #{CONFIG_FILE}"
end

file BOOK_EPUB => INPUT do
  FileUtils.rm_rf [BOOK_EPUB, BOOK, BOOK + '-epub']
  sh "review-epubmaker #{CONFIG_FILE}"
end

file WEBROOT => INPUT do
  FileUtils.rm_rf [WEBROOT]
  sh "review-webmaker #{CONFIG_FILE}"
end

file TEXTROOT => INPUT do
  FileUtils.rm_rf [TEXTROOT]
end

CLEAN.include([BOOK, BOOK_PDF, BOOK_EPUB, BOOK + '-pdf', BOOK + '-epub', WEBROOT, 'images/_review_math', TEXTROOT, OBJ])
