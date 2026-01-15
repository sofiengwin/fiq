module RailsAdmin
  module Config
    module Actions
      class FetchCareer < RailsAdmin::Config::Actions::Base
        register_instance_option :member do
          true
        end
        # This makes it a GET action
        register_instance_option :http_methods do
          [ :get, :post ]
        end

        # Action label/name
        register_instance_option :label do
          "Fetch Career"
        end

        register_instance_option :link_icon do
          "icon-briefcase"
        end

        # Controller action
        register_instance_option :controller do
          Proc.new do
            if @object.respond_to?(:fetch_data)
              @object.fetch_data
              flash[:success] = "Job queued to fetch data for #{@object.name}"
            else
              flash[:error] = "This object does not support fetching data."
            end
            redirect_to back_or_index
          end
        end
      end
    end
  end
end

# Register the custom action
RailsAdmin::Config::Actions.register(RailsAdmin::Config::Actions::FetchCareer)
