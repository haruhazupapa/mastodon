# frozen_string_literal: true

require 'singleton'

class Formatter
  include Singleton
  include RoutingHelper

  include ActionView::Helpers::TextHelper
  include ActionView::Helpers::SanitizeHelper

  def format(status)
    return reformat(status.content) unless status.local?

    html = status.text
    html = encode_and_link_urls(html)
    html = simple_format(html, {}, sanitize: false)
    html = html.delete("\n")
    html = link_mentions(html, status.mentions)
    html = link_hashtags(html)
    html = format_bbcode(html)

    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  def reformat(html)
    sanitize(html, tags: %w(a br p span), attributes: %w(href rel class))
  end

  def plaintext(status)
    return status.text if status.local?
    strip_tags(status.text)
  end

  def simplified_format(account)
    return reformat(account.note) unless account.local?

    html = encode_and_link_urls(account.note)
    html = link_accounts(html)
    html = link_hashtags(html)
    html = format_bbcode(html)

    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  private

  def encode(html)
    HTMLEntities.new.encode(html)
  end

  def encode_and_link_urls(html)
    entities = Twitter::Extractor.extract_urls_with_indices(html, extract_url_without_protocol: false)
    entities = entities.sort_by { |entity| entity[:indices].first }

    chars = html.to_s.to_char_a
    html_attrs = {
      target: '_blank',
      rel: 'nofollow noopener',
    }
    result = ''

    last_index = entities.reduce(0) do |index, entity|
      indices = entity[:indices]
      result += encode(chars[index...indices.first].join)
      result += Twitter::Autolink.send(:link_to_text, entity, link_html(entity[:url]), entity[:url], html_attrs)
      indices.last
    end
    result += encode(chars[last_index..-1].join)
  end

  def link_urls(html)
    Twitter::Autolink.auto_link_urls(html, url_target: '_blank',
                                           link_attribute_block: lambda { |_, a| a[:rel] << ' noopener' },
                                           link_text_block: lambda { |_, text| link_html(text) })
  end

  def link_mentions(html, mentions)
    html.gsub(Account::MENTION_RE) do |match|
      acct    = Account::MENTION_RE.match(match)[1]
      mention = mentions.find { |item| TagManager.instance.same_acct?(item.account.acct, acct) }

      mention.nil? ? match : mention_html(match, mention.account)
    end
  end

  def link_accounts(html)
    html.gsub(Account::MENTION_RE) do |match|
      acct = Account::MENTION_RE.match(match)[1]
      username, domain = acct.split('@')
      domain = nil if TagManager.instance.local_domain?(domain)
      account = Account.find_remote(username, domain)

      account.nil? ? match : mention_html(match, account)
    end
  end

  def link_hashtags(html)
    html.gsub(Tag::HASHTAG_RE) do |match|
      hashtag_html(match)
    end
  end

  def link_html(url)
    prefix = url.match(/\Ahttps?:\/\/(www\.)?/).to_s
    text   = url[prefix.length, 30]
    suffix = url[prefix.length + 30..-1]
    cutoff = url[prefix.length..-1].length > 30

    "<span class=\"invisible\">#{prefix}</span><span class=\"#{cutoff ? 'ellipsis' : ''}\">#{text}</span><span class=\"invisible\">#{suffix}</span>"
  end

  def hashtag_html(match)
    prefix, affix = match.split('#')
    "#{prefix}<a href=\"#{tag_url(affix.downcase)}\" class=\"mention hashtag\">#<span>#{affix}</span></a>"
  end

  def mention_html(match, account)
    "#{match.split('@').first}<span class=\"h-card\"><a href=\"#{TagManager.instance.url_for(account)}\" class=\"u-url mention\">@<span>#{account.username}</span></a></span>"
  end

  def format_bbcode(html)
    begin
      html = html.bbcode_to_html(false, {
        :spin => {
          :html_open => '<span class="fa fa-spin">', :html_close => '</span>',
          :description => 'Make text spin',
          :example => 'This is [spin]spin[/spin].'},
      }, :enable, :i, :b, :color, :quote, :code, :size, :u, :s, :spin)
    rescue Exception => e
    end
    html
  end
end
