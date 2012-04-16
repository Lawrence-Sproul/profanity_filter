module ProfanityFilter
  def self.included(base)
    # base.send :extend, ClassMethods
    base.class_eval do
      extend ClassMethods
    end
  end

  module ClassMethods
    def profanity_filter!(*attr_names)
      options = attr_names.extract_options!
      attr_names.each { |attr_name| setup_callbacks_for(attr_name, options) }
    end

    def profanity_filter(*attr_names)
      options = attr_names.extract_options!

      attr_names.each do |attr_name|
        instance_eval do
          define_method "#{attr_name}_clean" do; ProfanityFilter::Base.clean(self[attr_name.to_sym], options); end
          define_method "#{attr_name}_original" do; self[attr_name]; end
          define_method "profanity_filtered_attrs" do; attr_names; end
          alias_method attr_name.to_sym, "#{attr_name}_clean".to_sym
          
          define_method "unbind_profanity" do
            profanity_filtered_attrs.each do |attr_name|
              eval %(
                class << self
                  undef_method :#{attr_name}
                  def #{attr_name}
                    @attributes[%q(#{attr_name})]
                  end
                end
              )
            end
          end
          define_method "bind_profanity" do
            profanity_filtered_attrs.each do |attr_name|
              eval %(
                class << self
                  undef_method :#{attr_name}
                  alias_method :#{attr_name}, :#{attr_name}_clean
                end
              )
            end
          end
          
          #Before and after save does not get triggered until after the attributes have been accessed.
          #SO... lets override the save method.
          define_method "save" do |*args|
            unbind_profanity
            result = super(*args)
            bind_profanity
            return result
          end
        end
      end
    end

    def setup_callbacks_for(attr_name, options)
      before_validation do |record|
        record[attr_name.to_sym] = ProfanityFilter::Base.clean(record[attr_name.to_sym], options)
      end
    end
  end

  class Base
    cattr_accessor :replacement_text, :dictionary_file, :dictionary, :whitelist, :whitelist_file, :leet_speak
    @@replacement_text = '@#$%'
    @@dictionary_file  = File.join(File.dirname(__FILE__), '../config/dictionary.yml')
    @@whitelist_file = File.join(File.dirname(__FILE__), '../config/whitelist.yml')

    class << self
      def dictionary
        @@dictionary ||= YAML.load_file(@@dictionary_file)
      end
      
      def append_dictionary( file )
        @@dictionary = dictionary.merge(YAML.load_file( file ) )
      end
      
      def whitelist
        @@whitelist ||= YAML.load_file(@@whitelist_file)
      end
      
      def remove_from_dictionary( file )
        excluded_words = YAML.load_file( file )
        if excluded_words
          dictionary.reject! do |dictionary_word|
            excluded_words.include? dictionary_word
          end
        end
      end
      
      def banned?(word = '')
        if word
          dictionary.include?(word.downcase) || (leet_speak && (leet_words(word.downcase) & dictionary.keys).any?)
        end
      end
      
      def profane?(text = '', options = {})
        text == clean(text, options) ? false : true
      end

      def clean(text, options = {})
        return text if text.blank?
        if options.is_a?(String)
          @replace_method = options 
        else
          @replace_method = options[:method]
          self.leet_speak = options[:leet]
        end
        text.split(/(\s)/).collect{ |word| clean_word(word) }.join
      end

      def clean_word(word)
        if word.strip.size <= 2 or whitelist.include?(word.downcase)
          return word
        end

        if word.index(/[\W]/)
          word = word.split(/(\W)/).collect{ |subword| clean_word(subword) }.join
          concat = word.gsub(/\W/, '')
          word = concat if banned? concat
        end

        banned?(word) ? replacement(word) : word
       end

       def replacement(word)
         case @replace_method
         when 'dictionary'
           dictionary[word.downcase] || replacement_text
         when 'vowels'
           word.gsub(/[aeiou]/i, '*')
         when 'hollow'
           word[1..word.size-2] = '*' * (word.size-2) if word.size > 2
           word
         when 'stars'
           '*' * word.size
         else
           replacement_text
         end
       end
       
       def leet_words(word)
         [ word.gsub(/(4|@|\/\-\\|\/\\|\^)/, 'a'),
           word.gsub(/(8|\|3|6|13||\]3)/, 'b'),
           word.gsub(/(\(|\<|\{)/, 'c'),
           word.gsub(/(\|\)|\[\)|\]\)|I\>|\|\>|0)/, 'd'),
           word.gsub(/(3|\&|\[\-)/, 'e'),
           word.gsub(/(\|\=|\]\=|\}|ph|\(\=)/, 'f'),
           word.gsub(/(6|9|\&|\(_\+|C\-|cj)/, 'g'),
           word.gsub(/(\|\-\||\#|\]\-\[|\[\-\]|\)\-\(|\(\-\)|\:\-\:|\}\{|\}\-\{)/, 'h'),
           word.gsub(/(\!|1|\|)/, 'i'),
           word.gsub(/(\_\||\_\/|\]|\<\/|\_\))/, 'j'),
           word.gsub(/(X|\|\<|\|X|\|\{)/, 'k'),
           word.gsub(/(1|7|\|_|\||\|\_)/, 'l'),
          word.gsub( /(44|\/\\\/\\|\|\\\/\||\|v\||IYI|IVI|\[V\]|\^\^|\/\/\\\\\/\/\\\\|\(V\)|\(\\\/\)|\/\|\\|\/\|\/\||\.\\\\|\/\^\^\\|\/\V\\|\|\^\^\||AA)/, 'm'),
           word.gsub(/(\|\\\||\/\\\/|\/\/\\\\\/\/|\[\\\]|\<\\\>|\{\\\}|\/\/|\[\]\\\[\]|\]\\\[|\~)/, 'n'),
           word.gsub(/(0|\(\)|\[\])/, 'o'),
           word.gsub(/(\|\*|\|o|\|\>|\|\"|\?|9|\[\]D|\|7|\|D)/, 'p'),
           word.gsub(/(0_|0,|\(,\)|\<\||9)/, 'q'),
           word.gsub(/(\|2|2|\/2|I2|\|\^|\|\~|lz|\|2|\[z|\|\`|\l2|.\-)/, 'r'),
           word.gsub(/(5|\$|z)/, 's'),
           word.gsub(/(7|\+|\-\|\-|1|\'\]\[\')/, 't'),
           word.gsub(/(\|\_\||\(_\)|M|\[_\]|\\\_\/|\\\_\\|\/\_\/)/, 'u'),
           word.gsub(/(\\\/|\\\\\/\/)/, 'v'),
           word.gsub(/(\\\/\\\/|vv|\'\/\/|\\\\\'|\\\^\/|\(n\)|\\X\/|\\\|\/|\\_\|_\/|\\\\\/\/\\\\\/\/|\\_\:_\/|\]I\[|UU)/, 'w'),
           word.gsub(/(\%|\>\<|\}\{|\*|\)\()/, 'x'),
           word.gsub(/(j|\`\/|\`\(|\-\/|\'\/)/, 'y'),
           word.gsub(/(2|\~\/_|\%|7_)/, 'z')].uniq
       end
    end
  end
end

ActiveRecord::Base.send(:include, ProfanityFilter) if defined?(ActiveRecord)
