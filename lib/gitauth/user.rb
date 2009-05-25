#--
#   Copyright (C) 2009 Brown Beagle Software
#   Copyright (C) 2008 Darcy Laycock <sutto@sutto.net>
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Affero General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Affero General Public License for more details.
#
#   You should have received a copy of the GNU Affero General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#++


module GitAuth
  class User < SaveableClass(:users)
        
    def self.get(name)
      GitAuth.logger.debug "Getting user for the name '#{name}'"
      self.all.detect { |r| r.name == name }
    end
    
    def self.create(name, admin, key)
      # Basic sanity checking.
      return false if name.nil? || admin.nil? || key.nil?
      return false unless name =~ /^([\w\_\-\.]+)$/ && !!admin == admin
      user = self.new(name, admin)
      if user.write_ssh_key!(key)
        self.add_item(user)
        return true
      else
        return false
      end
    end
    
    attr_reader :name, :admin
    
    def initialize(name, admin = false)
      @name = name
      @admin = admin
    end
    
    def to_s
      @name.to_s
    end
    
    def write_ssh_key!(key)
      cleaned_key = self.class.clean_ssh_key(key)
      if cleaned_key.nil?
        return false
      else
        output = "#{command_prefix} #{cleaned_key}"
        File.open(GitAuth.settings.authorized_keys_file, "a+") do |file|
          file.puts output
        end
        return true
      end
    end
    
    def command_prefix
      "command=\"#{GitAuth.settings.shell_executable} #{@name}\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding#{shell_accessible? ? "" : ",no-pty"}"
    end
    
    def destroy!
      GitAuth::Repo.all.each  { |r| r.remove_permissions_for(self) }
      GitAuth::Group.all.each { |g| g.remove_member(self) }
      # Remove the public key from the authorized_keys file.
      auth_keys_path = GitAuth.settings.authorized_keys_file
      if File.exist?(auth_keys_path)
        contents = File.read(auth_keys_path)
        contents.gsub!(/#{command_prefix} ssh-\w+ [a-zA-Z0-9\/\+]+==\r?\n?/m, "")
        File.open(auth_keys_path, "w+") { |f| f.write contents }
      end
      self.class.all.reject! { |u| u == self }
      # Finally, save everything
      self.class.save!
      GitAuth::Repo.save!
      GitAuth::Group.save!
    end
    
    def admin?
      !!@admin
    end
    
    def shell_accessible?
      admin?
    end
    
    def pushable?(repo)
      admin? || repo.writeable_by?(self)
    end
    
    def pullable?(repo)
      admin? || repo.readable_by?(self)
    end
    
    def can_execute?(command, repo)
      return nil if command.bad?
      if command.write?
        GitAuth.logger.debug "Checking if #{self.name} can push to #{repo.name}"
        return self.pushable?(repo)
      else
        GitAuth.logger.debug "Checking if #{self.name} can pull from #{repo.name}"
        return self.pullable?(repo)
      end
    end
    
    def self.clean_ssh_key(key)
      if key =~ /^(ssh-\w+ [a-zA-Z0-9\/\+]+==).*$/
        return $1
      else
        return nil
      end
    end
    
  end
  Users = User # For Backwards Compat.
end