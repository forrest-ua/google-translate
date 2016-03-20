#encoding: UTF-8

require 'net/http'
require 'json'
require 'tempfile'
require 'resource_accessor'

class GoogleTranslate
  GOOGLE_TRANSLATE_SERVICE_URL = "https://translate.google.com"
  GOOGLE_SPEECH_SERVICE_URL    = "http://translate.google.com/translate_tts"

  def supported_languages
    response = call_service GOOGLE_TRANSLATE_SERVICE_URL

    from_languages = collect_languages response.body, 0, 'sl', 'gt-sl'
    to_languages   = collect_languages response.body, 1, 'tl', 'gt-tl'

    [from_languages, to_languages]
  end

  def translate(from_lang, to_lang, text, options={})
    raise("Missing 'from' language") unless from_lang
    raise("Missing 'to' language") unless to_lang
    raise("Missing text for translation") unless text

    r = call_translate_service(from_lang, to_lang, text)

    result = JSON.parse(r.gsub('[,', '['))

    raise("Translate Server is down") if (!result || result.empty?)

    result
  end

  def say lang, text
    speech_content = call_speech_service(lang, text)

    file = Tempfile.new('.google_translate_speech---')

    file.write(speech_content)

    file.close

    system "afplay #{file.path}"

    file.unlink
  end

  private

  def translate_url(from_lang, to_lang)
    url = "#{GOOGLE_TRANSLATE_SERVICE_URL}/translate_a/single"
    params = "client=t&sl=#{from_lang}&tl=#{to_lang}&hl=en&dt=bd&dt=ex&dt=ld&dt=md&dt=qc&dt=rw&dt=rm&dt=ss" +
             "&dt=t&dt=at&dt=sw&ie=UTF-8&oe=UTF-8&prev=btn&rom=1&ssel=0&tsel=0"

    "#{url}?#{params}"
  end

  def speech_url(lang)
    "#{GOOGLE_SPEECH_SERVICE_URL}?tl=#{lang}&ie=UTF-8&oe=UTF-8"
  end

  def call_translate_service from_lang, to_lang, text
    url = translate_url(from_lang, to_lang)

    response = call_service "#{url}&tk=" + tl(text), "q=#{text}"

    response.body.split(',').collect { |s| s == '' ? "\"\"" : s }.join(",") # fix json object
  end

  def call_speech_service lang, text
    url = speech_url(lang)

    response = call_service url, "q=#{text}"

    response.body
  end

  def call_service url, body
    accessor = ResourceAccessor.new

    accessor.get_response({:url => url, :method => :post, :body => body}, 
        {'User-Agent' => 'Mozilla/5.0 (iPhone; U; CPU iPhone OS 4_3_3 like Mac OS X; en-us) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8J2 Safari/6533.18.5'})
  end

  def collect_languages buffer, index, tag_name, tag_id
    spaces = '\s?'
    quote  = '(\s|\'|")?'

    id_part       = "id#{spaces}=#{spaces}#{quote}#{tag_id}#{quote}"
    name_part     = "name#{spaces}=#{spaces}#{quote}#{tag_name}#{quote}"
    class_part    = "class#{spaces}=#{spaces}#{quote}(.*)?#{quote}"
    tabindex_part = "tabindex#{spaces}=#{spaces}#{quote}0#{quote}"
    phrase        = "#{spaces}#{id_part}#{spaces}#{name_part}#{spaces}#{class_part}#{spaces}#{tabindex_part}#{spaces}"

    re1 = buffer.split(%r{<select#{phrase}>(.*)?</select>}).select { |x| x =~ %r{<option} }

    stopper = "</select>"

    text = re1[index]

    if index == 0
      pos  = text.index(stopper)
      text = text[0..pos]
    end

    re2     = /<option(\s*)value="([a-z|A-Z|-]*)">([a-z|A-Z|\(|\)|\s]*)<\/option>/
    matches = text.gsub(/selected/i, '').squeeze.scan(re2)

    if matches.size == 0
      re2     = /<option(\s*)value=([a-z|A-Z|-]*)>([a-z|A-Z|\(|\)|\s]*)<\/option>/
      matches = text.gsub(/selected/i, '').squeeze.scan(re2)
    end

    matches.map { |m| Language.new(m[2], m[1]) }
  end


  def shr32(x, bits)
    return x if bits.to_i <= 0
    return 0 if bits.to_i >= 32

    bin = x.to_i.to_s(2) # to binary
    l = bin.length
    if l > 32
      bin = bin[(l - 32), 32]
    elsif l < 32
      bin = bin.rjust(32, '0')
    end

    bin = bin[0, (32 - bits)]
    (bin.rjust(32, '0')).to_i(2)
  end

  def char_code_at(str, index)
    str[index].ord
  end

  def rl(a, b)
    c = 0
    while c < (b.length - 2) do
      d = b[c+2]
      d = (d >= 'a') ? char_code_at(d, 0) - 87 : d.to_i
      d = (b[c+1] ==  '+') ? shr32(a, d) : a << d
      a = (b[c] == '+') ? (a + d & 4294967295) : a ^ d
      c += 3
    end
    a
  end

  def generate_b
    ((Time.new() - Time.new(1970,1,1)) / 3600).floor
  end

  def tl(a)
    b = generate_b
    d = []
    e = 0
    f = 0

    while f < a.length do
      g = char_code_at(a, f)
      if 128 > g
        d[e] = g
        e += 1
      else
        if 2048 > g
          d[e] = g >> 6 | 192
          e += 1
        else
          if (55296 == (g & 64512) && f + 1 < a.length && 56320 == (char_code_at(a, (f+1)) & 64512))
            g = 65536 + ((g & 1023) << 10) + (char_code_at(a, ++f) & 1023)
            d[e] = g >> 18 | 240
            e += 1
            d[e] = g >> 12 & 63 | 128
            e += 1
          else
            d[e] = g >> 12 | 224
            e += 1
            d[e] = g >> 6 & 63 | 128
            e += 1
          end
        end
        d[e] = g & 63 | 128
        e += 1
      end
      f += 1
    end

    a = b
    e = 0

    while e < d.length do
      a += d[e]
      a = rl(a, '+-a^+6')
      e += 1
    end

    a = rl(a, "+-3^+b+-f")
    a = (a & 2147483647) + 2147483648 if 0 > a
    a %= 10 ** 6
    return ("#{ a }.#{ a ^ b }")
  end

end


