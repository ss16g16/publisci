module Prov
  module DSL

    class Singleton
      include Prov::DSL
    end

    def self.included(mod)
      Prov.registry.clear
    end

    def agent(*args, &block)
      if block_given?
        a = Prov::Agent.new
        a.instance_eval(&block)
        a.__label=args[0]
        Prov.register(args[0], a)
      else
        name = args.shift
        args = Hash[*args]
        a = Prov::Agent.new

        raise "NoSubject: Agent #{a} was not given a subject" unless args[:subject]

        a.subject args[:subject]

        (args.keys - [:subject]).map{|k|
          raise "Unkown agent setting #{k}" unless try_auto_set(a,k,args[k])
        }

        a.__label=name

        Prov.register(name, a)
      end
    end

    def organization(*args,&block)
      newargs = [args.shift]
      args=Hash[*args]
      args[:type] = :organization
      newargs << args
      agent(*newargs,&block)
    end

    def entity(*args, &block)
      if block_given?
        e = Prov::Entity.new
        e.instance_eval(&block)
        e.__label=args[0]
        Prov.register(args[0], e)
      else
        name = args.shift
        args = Hash[*args]
        e = Prov::Entity.new

        e.subject args[:subject]
        (args.keys - [:subject]).map{|k|
          raise "Unkown entity setting #{k}" unless try_auto_set(e,k,args[k])
        }

        e.__label=name

        Prov.register(name, e)
      end
    end
    alias_method :data, :entity

    def plan(*args, &block)
      if block_given?
        p = Prov::Plan.new
        p.instance_eval(&block)
        p.__label=args[0]
        Prov.register(args[0], e)
      else
        name = args.shift
        args = Hash[*args]
        p = Prov::Plan.new

        p.__label=name
        p.subject args[:subject]
        (args.keys - [:subject]).map{|k|
          raise "Unkown plan setting #{k}" unless try_auto_set(p,k,args[k])
        }


        Prov.register(name, p)
      end
    end

    def activity(*args, &block)
      if block_given?
        act = Prov::Activity.new
        act.instance_eval(&block)
        act.__label=args[0]
        Prov.register(args[0], act)
      else
        name = args.shift
        args = Hash[*args]

        act.subject args[:subject]

        (args.keys - [:subject]).map{|k|
          raise "Unkown agent setting #{k}" unless try_auto_set(act,k,args[k])
        }

        a = Prov::Activity.new

        act.__label=name
        Prov.register(name, act)
        raise "has based activity creation not yet implemented"
      end
    end

    def generate_n3(abbreviate = false)
      entities = Prov.entities.values.map(&:to_n3).join
      agents = Prov.agents.values.map(&:to_n3).join
      activities = Prov.activities.values.map(&:to_n3).join
      associations = Prov.associations.map(&:to_n3).join
      plans = Prov.plans.values.map(&:to_n3).join

      str = entities + agents + activities + associations + plans

      if abbreviate
        abbreviate_known(str)
      else
        str
      end
    end

    def return_objects
      Prov.registry
    end

    private
    def try_auto_set(object,method,args)
      if object.methods.include? method
        object.send(method,args)
        true
      else
        false
      end
    end

    def abbreviate_known(turtle)
      ttl = turtle.dup
      %w{activity assoc agent}.each{|element|
        ttl.gsub!(%r{<#{Prov.base_url}/#{element}/([\w|\d]+)>}, "#{element}:" + '\1')
      }

      ttl.gsub!(%r{<http://gsocsemantic.wordpress.com/([\w|\d]+)>}, 'me:\1')
      ttl
    end
  end
end