#require "rubygems"
#require "rinruby"

module LIB
  class StatisticalTest
  
    # -1 -> array1 < array2
    # 0 -> not difference
    # 1 -> array2 > array1
    #
    def self.pairedTTest(array1, array2, significance_level=0.95)
      
      @@r = RinRuby.new(true,false) unless defined?(@@r) and @@r 
      @@r.assign "v1",array1
      @@r.assign "v2",array2
      @@r.eval "ttest = t.test(v1,v2,paired=T)"
      t = @@r.pull "ttest$statistic"
      p = @@r.pull "ttest$p.value"
      if (1-significance_level > p)
        t
      else
        0
      end
    end
    
    def self.quit_r
      begin
        @@r.quit
        @@r = nil
      rescue
      end
    end
  end
end

module Reports
 
  class ReportStatisticalTest
    
    # __grouped_validations__ : array of validation arrays
    def self.test_matrix( validations, group_attribute, test_attribute, class_value, test_method="paired_ttest", significance_level=0.95 )
      
      raise "statistical-test: '"+test_method+"' does not exist" unless ReportStatisticalTest.respond_to?(test_method)
      grouped_validations = Reports::Util.group(validations, [group_attribute])
      LOGGER.debug "perfom test '"+test_method.to_s+"' for '"+test_attribute.to_s+"' for #"+grouped_validations.size.to_s+" "+group_attribute.to_s
      
      titles = []
      matrix = []
      grouped_validations.size.times do |i|
        
        validations1 = grouped_validations[i]
        title1 = validations1[0].send(group_attribute)
        titles << title1
        matrix[i] = [] unless matrix[i]
        
        grouped_validations.size.times do |j|
          if (i == j)
            matrix[i][j] = nil
          else
            validations2 = grouped_validations[j]
            title2 = validations2[0].send(group_attribute)
            matrix[i][j] = ReportStatisticalTest.send(test_method,validations1,validations2,
              test_attribute, class_value, significance_level)
          end
        end
      end
      {:titles => titles, :matrix => matrix, :num_results => grouped_validations[0].size}
    end
    
    def self.paired_ttest( validations1, validations2, attribute, class_value, significance_level=0.95 )
      
      array1 = validations1.collect{ |v| (v.send(attribute).is_a?(Hash) ? v.send(attribute)[class_value].to_f : v.send(attribute).to_f) }
      array2 = validations2.collect{ |v| (v.send(attribute).is_a?(Hash) ? v.send(attribute)[class_value].to_f : v.send(attribute).to_f) }
      LOGGER.debug "paired-t-testing "+attribute.to_s+" "+array1.inspect+" vs "+array2.inspect
      LIB::StatisticalTest.pairedTTest(array1, array2, significance_level)
    end
    
    def self.quit_r
      LIB::StatisticalTest.quit_r
    end

  end

end

#x=["1.36840891838074", "2.89500403404236", "2.58440494537354", "1.96544003486633", "1.4017288684845", "1.68250012397766", "1.65089893341064", "2.24862003326416", "3.73909902572632", "2.36335206031799"]
#y=["1.9675121307373", "2.30981087684631", "2.59359288215637", "2.62243509292603", "1.98700189590454", "2.26789593696594", "2.03917217254639", "2.69466996192932", "1.96487307548523", "1.65820598602295"]
#puts LIB::StatisticalTest.pairedTTest(x,y)
#
##t1 = Time.new
##10.times do
#  puts LIB::StatisticalTest.pairedTTest([1.01,2,3,4,5,12,4,2],[2,3,3,3,56,3,4,5])
##end
#LIB::StatisticalTest.quit_r
##t2 = Time.new
##puts t2-t1


