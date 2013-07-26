  #monkey patch to make rdf string w/ heredocs prettier ;)
class String
  def unindent
    gsub /^#{self[/\A\s*/]}/, ''
  end
end

module R2RDF
  class Dataset
    module DataCube
      include R2RDF::Parser
      def defaults
      {
        type: :dataframe,
        encode_nulls: false,
        base_url: "http://www.rqtl.org",
      }
      end

      def generate_resources(measures, dimensions, codes, options={})
        newm = measures.map {|m|
          if m =~ /^http:\/\//
            "<#{m}>"
          elsif m =~ /^[a-zA-z]+:[a-zA-z]+$/
            m
          else
            "prop:#{m}"
          end
        }

        newc = []

        newd = dimensions.map{|d|
            if d =~ /^http:\/\//
              # newc << "<#{d}>" if codes.include? d
              "<#{d}>"
            elsif d =~ /^[a-zA-z]+:[a-zA-z]+$/
              d
            else
              # newc << "prop:#{d}" if codes.include? d
              "prop:#{d}"
            end
        }

        if codes.first.is_a? Array
          newc = codes.map{|c|
            c.map{|el|
              if el =~ /^http:\/\//
                "<#{el}>"
              else
                el
              end
            }
          }
        else
          newc = codes.map{|c|
              ["#{sanitize(c).first}","code:#{sanitize(c).first.downcase}","code:#{sanitize(c).first.downcase.capitalize}"]
          }
        end
        [newm, newd, newc]
      end

      def encode_data(codes,data,var,options={})
        codes = sanitize(codes)
        new_data = {}
        data.map{|k,v|
          if codes.include? k
            new_data[k] = v.map{|val|
              if val =~ /^http:\/\//
                "<#{val}>"
              elsif val =~ /^[a-zA-z]+:[a-zA-z]+$/
                val
              else
                "<code/#{k.downcase}/#{val}>"
              end
            }
          else
            new_data[k] = v
          end
        }
        new_data
      end

      def vocabulary(vocab,options={})
        if vocab.is_a?(String) && vocab =~ /^http:\/\//
          RDF::Vocabulary.new(vocab)
        elsif RDF.const_defined? vocab.to_sym && RDF.const_get(vocab.to_sym).inspect =~ /^RDF::Vocabulary/
          RDF.const_get(vocab)
        else
          nil
        end
      end

      def generate(measures, dimensions, codes, data, observation_labels, var, options={})
        # dimensions = sanitize(dimensions)
        # codes = sanitize(codes)
        # measures = sanitize(measures)
        var = sanitize([var]).first
        data = sanitize_hash(data)

        str = prefixes(var,options)
        str << data_structure_definition(measures, dimensions, codes, var, options)
        str << dataset(var, options)
        # component_specifications(measures, dimensions, var, options).map{ |c| str << c }
        dimension_properties(dimensions, codes, var, options).map{|p| str << p}
        measure_properties(measures, var, options).map{|p| str << p}
        code_lists(codes, data, var, options).map{|l| str << l}
        concept_codes(codes, data, var, options).map{|c| str << c}
        observations(measures, dimensions, codes, data, observation_labels, var, options).map{|o| str << o}
        str
      end

      def prefixes(var, options={})
        var = sanitize([var]).first
        options = defaults().merge(options)
        base = options[:base_url]
        <<-EOF.unindent
        @base <#{base}/ns/dc/> .
        @prefix ns:    <#{base}/ns/dataset/#{var}#> .
        @prefix qb:    <http://purl.org/linked-data/cube#> .
        @prefix rdf:   <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
        @prefix rdfs:  <http://www.w3.org/2000/01/rdf-schema#> .
        @prefix prop:  <#{base}/dc/properties/> .
        @prefix dct:   <http://purl.org/dc/terms/> .
        @prefix xsd:   <http://www.w3.org/2001/XMLSchema#> .
        @prefix cs:    <#{base}/dc/dataset/#{var}/cs/> .
        @prefix code:  <#{base}/dc/dataset/#{var}/code/> .
        @prefix owl:   <http://www.w3.org/2002/07/owl#> .
        @prefix skos:  <http://www.w3.org/2004/02/skos/core#> .
        @prefix foaf:     <http://xmlns.com/foaf/0.1/> .
        @prefix org:      <http://www.w3.org/ns/org#> .
        @prefix prov:     <http://www.w3.org/ns/prov#> .

        EOF
      end

      def data_structure_definition(measures,dimensions,codes,var,options={})
        var = sanitize([var]).first
        options = defaults().merge(options)
        rdf_measures, rdf_dimensions, rdf_codes  = generate_resources(measures, dimensions, codes, options)

        str = "ns:dsd-#{var} a qb:DataStructureDefinition;\n"
        rdf_dimensions.map{|d|
          str << "  qb:component [ qb:dimension #{d} ] ;\n"
        }

        rdf_measures.map{|m|
          str << "  qb:component [ qb:measure #{m} ] ;\n"
        }
        str[-2]='.'
        str<<"\n"
        str
      end

      def dataset(var,options={})
        var = sanitize([var]).first
        options = defaults().merge(options)
        <<-EOF.unindent
        ns:dataset-#{var} a qb:DataSet ;
          rdfs:label "#{var}"@en ;
          qb:structure ns:dsd-#{var} .

        EOF
      end

      def component_specifications(measure_names, dimension_names, var, options={})
        options = defaults().merge(options)
        specs = []

          dimension_names.map{|d|
          specs << <<-EOF.unindent
            cs:#{d} a qb:ComponentSpecification ;
              rdfs:label "#{d} Component" ;
              qb:dimension prop:#{d} .

            EOF
          }

          measure_names.map{|n|
            specs << <<-EOF.unindent
              cs:#{n} a qb:ComponentSpecification ;
                rdfs:label "#{n} Component" ;
                qb:measure prop:#{n} .

              EOF
          }

        specs
      end

      def dimension_properties(dimensions, codes, var, options={})
        options = defaults().merge(options)
        rdf_measures, rdf_dimensions, rdf_codes  = generate_resources([], dimensions, codes, options)
        props = []

        dimension_codes = rdf_codes.map{|c|
          if c[0]=~/^<http:/
            c[0][1..-2]
          else
            c[0]
          end
        }

        rdf_dimensions.each_with_index{|d,i|
          if dimension_codes.include?(dimensions[i])
            code = rdf_codes[dimension_codes.index(dimensions[i])]
            props << <<-EOF.unindent
            #{d} a rdf:Property, qb:DimensionProperty ;
              rdfs:label "#{strip_prefixes(strip_uri(d))}"@en ;
              qb:codeList #{code[1]} ;
              rdfs:range #{code[2]} .

            EOF
          else
            props << <<-EOF.unindent
            #{d} a rdf:Property, qb:DimensionProperty ;
              rdfs:label "#{strip_prefixes(strip_uri(d))}"@en .

            EOF
          end
          }

        props
      end

      def measure_properties(measures, var, options={})
        options = defaults().merge(options)
        rdf_measures = generate_resources(measures, [], [], options)[0]
        props = []

          rdf_measures.map{ |m|

            props <<  <<-EOF.unindent
            #{m} a rdf:Property, qb:MeasureProperty ;
              rdfs:label "#{strip_prefixes(strip_uri(m))}"@en .

            EOF
            }

        props
      end

      def observations(measures, dimensions, codes, data, observation_labels, var, options={})
        var = sanitize([var]).first
        measures = sanitize(measures)
        dimensions = sanitize(dimensions)
        options = defaults().merge(options)
        rdf_measures, rdf_dimensions, rdf_codes  = generate_resources(measures, dimensions, codes, options)
        data = encode_data(codes, data, var, options)
        obs = []

        dimension_codes = rdf_codes.map{|c|
          if c[0]=~/^<http:/
            c[0][1..-2]
          else
            c[0]
          end
        }

        observation_labels.each_with_index.map{|r, i|
          contains_nulls = false
          str = <<-EOF.unindent
          ns:obs#{r} a qb:Observation ;
            qb:dataSet ns:dataset-#{var} ;
          EOF

          str << "  rdfs:label \"#{r}\" ;\n" unless options[:no_labels]

          dimensions.each_with_index{|d,j|
            contains_nulls = contains_nulls | (data[d][i] == nil)

            if dimension_codes.include? d
              # str << "  #{rdf_dimensions[j]} <code/#{d.downcase}/#{data[d][i]}> ;\n"
              str << "  #{rdf_dimensions[j]} #{to_resource(data[d][i], options)} ;\n"
            else
              str << "  #{rdf_dimensions[j]} #{to_literal(data[d][i], options)} ;\n"
            end
          }

          measures.each_with_index{|m,j|
            contains_nulls = contains_nulls | (data[m][i] == nil)
            str << "  #{rdf_measures[j]} #{to_literal(data[m][i], options)} ;\n"

          }

          str << "  .\n\n"
          if contains_nulls && !options[:encode_nulls]
            if options[:raise_nils]
              raise "missing component for observation, skipping: #{str}, "
            elsif options[:whiny_nils]
              puts "missing component for observation, skipping: #{str}, "
            end
          else
            obs << str
          end
        }
        obs
      end

      def code_lists(codes, data, var, options={})
        options = defaults().merge(options)
        rdf_measures, rdf_dimensions, rdf_codes  = generate_resources([], [], codes, options)
        data = encode_data(codes, data, var, options)
        lists = []
        rdf_codes.map{|code|
          if code[0] =~ /^<.+>$/
            refcode = code[0][1..-2]
          else
            refcode = code[0]
          end
          str = <<-EOF.unindent
            #{code[2]} a rdfs:Class, owl:Class;
              rdfs:subClassOf skos:Concept ;
              rdfs:label "Code list for #{strip_prefixes(strip_uri(code[1]))} - codelist class"@en;
              rdfs:comment "Specifies the #{strip_prefixes(strip_uri(code[1]))} for each observation";
              rdfs:seeAlso #{code[1]} .

            #{code[1]} a skos:ConceptScheme;
              skos:prefLabel "Code list for #{strip_prefixes(strip_uri(code[1]))} - codelist scheme"@en;
              rdfs:label "Code list for #{strip_prefixes(strip_uri(code[1]))} - codelist scheme"@en;
              skos:notation "CL_#{strip_prefixes(strip_uri(code[1])).upcase}";
              skos:note "Specifies the #{strip_prefixes(strip_uri(code[1]))} for each observation";
          EOF
          data[refcode].uniq.map{|value|
            unless value == nil && !options[:encode_nulls]
              str << "  skos:hasTopConcept #{to_resource(value,options)} ;\n"
            end
          }

          str << "  .\n\n"
          lists << str
        }


        lists
      end

      def concept_codes(codes, data, var, options={})
        options = defaults().merge(options)
        rdf_measures, rdf_dimensions, rdf_codes  = generate_resources([], [], codes, options)
        concepts = []
        data = encode_data(codes, data, var, options)
        rdf_codes.map{|code|
          if code[0] =~ /^<.+>$/
            refcode = code[0][1..-2]
          else
            refcode = code[0]
          end
          data[refcode].uniq.each_with_index{|value,i|
            unless value == nil && !options[:encode_nulls]
            concepts << <<-EOF.unindent
              #{to_resource(value,options)} a skos:Concept, #{code[2]};
                skos:topConceptOf #{code[1]} ;
                skos:prefLabel "#{strip_uri(data[refcode][i])}" ;
                skos:inScheme #{code[1]} .

            EOF
            end
          }
        }

        concepts
      end


      def abbreviate_known(turtle_string)
        #debug method
        # puts turtle_string
        turtle_string.gsub(/<http:\/\/www\.rqtl\.org\/dc\/properties\/(\S+)>/, 'prop:\1').gsub(/<http:\/\/www.rqtl.org\/ns\/dc\/code\/(\S+)\/(\S+)>/, '<code/\1/\2>').gsub(/<http:\/\/www.rqtl.org\/dc\/dataset\/(\S+)\/code\/(\S+)>/, 'code:\2')
      end
    end
  end
end
