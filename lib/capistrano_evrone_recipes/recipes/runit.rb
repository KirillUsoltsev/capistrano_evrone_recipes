_cset(:runit_export_path)   { "#{latest_release}/var/services" }
_cset(:runit_services_path) { "#{deploy_to}/services" }
_cset(:runit_export_cmd)    { "#{fetch :bundle_cmd} exec foreman export runitu" }
_cset(:runit_procfile)      { "Procfile" }
_cset(:foreman_concurency)  { nil }

namespace :runit do

  desc "Restart Procfile services"
  task :restart, :roles => :worker, :on_no_matching_servers => :continue, :except => { :no_release => true } do
    if find_servers_for_task(current_task).any?
      cmd = %Q{
        if [ -d #{runit_export_path} ] ; then
          echo "Update services" ;
          rm -rf #{runit_services_path}/* ;
          sync ;
          cp -r #{runit_export_path}/* #{runit_services_path}/ ;
          sync ;
          rm -rf #{runit_export_path} ;
        else
          echo "Restart services" ;
          sv t #{runit_services_path}/* ;
        fi
      }.compact
      run cmd
    end
  end

  desc "Stop services"
  task :stop, :roles => :worker, :on_no_matching_servers => :continue, :except => { :no_release => true } do
    if find_servers_for_task(current_task).any?
      cmd = "for i in `ls -1 #{runit_services_path}/`; do"
      cmd << " sv -w 10 force-stop #{runit_services_path}/${i} ; done"
      run(cmd)
    end
  end

  desc "Start services"
  task :start, :roles => :worker, :on_no_matching_servers => :continue, :except => { :no_release => true } do
    if find_servers_for_task(current_task).any?
      cmd = "for i in `ls -1 #{runit_services_path}/`; do"
      cmd << " sv -v -w 10 up #{runit_services_path}/${i} ; done"
      run(cmd)
    end
  end

  desc "Export Procfile"
  task :export, :roles => :worker, :on_no_matching_servers => :continue, :except => { :no_release => true } do
    if find_servers_for_task(current_task).any?
      CapistranoEvroneRecipes::Util.ensure_changed_remote_files(self, fetch(:runit_procfile)) do
        env = %{ RAILS_ENV=#{rails_env} }.strip + "\n"
        put(env, "#{runit_services_path}/.env")

        c = fetch(:foreman_concurency) ? "-c #{fetch :foreman_concurency}" : ""
        cmd = %{
          cd #{latest_release} &&
          #{runit_export_cmd} #{runit_export_path}
            -e #{runit_services_path}/.env
            -l #{shared_path}/log
            -f #{latest_release}/#{runit_procfile}
            --root=#{current_path}
            -a #{application} #{c} > /dev/null
        }.compact
        run cmd

        cmd = %{
          for i in $(ls #{runit_export_path}/); do
            sed -i 's|#{runit_export_path}|#{runit_services_path}|g' #{runit_export_path}/${i}/run ;
          done
        }.compact
        run cmd
      end
    end
  end
end

after "deploy:finalize_update", "runit:export"
after "deploy:start", "runit:start"
after "deploy:stop", "runit:stop"
after "deploy:restart", "runit:restart"
