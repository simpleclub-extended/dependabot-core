# frozen_string_literal: true

# TODO: File and specs need to be updated

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module Pub
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [/^pubspec\.yaml$/, /^pubspec\.lock$/]
      end

      def updated_dependency_files
        updated_files = []

        pubspec_file_pairs.each do |files|
          next unless file_changed?(files[:yaml]) || file_changed?(files[:lock])

          updated_contents = updated_pubspec_file_contents(files)
          content_changed = false

          if updated_contents[:yaml] != files[:yaml].content
            content_changed = true
            updated_files << updated_file(file: files[:yaml], content: updated_contents[:yaml])
          end

          if updated_contents[:lock] != files[:lock].content
            content_changed = true
            updated_files << updated_file(file: files[:lock], content: updated_contents[:lock])
          end

          raise "Content didn't change!" unless content_changed
        end

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def updated_pubspec_file_contents(files)
        yaml_file_name = files[:yaml].name
        lock_file_name = files[:lock].name
        yaml_content = files[:yaml].content
        lock_content = files[:lock].content if files[:lock]

        # TODO: Cache this information somehow for other dependencies.
        SharedHelpers.in_a_temporary_directory do
          File.write(yaml_file_name, yaml_content)
          File.write(lock_file_name, lock_content)

          # TODO: Use Flutter tool for Flutter projects
          SharedHelpers.with_git_configured(credentials: credentials) do
            SharedHelpers.run_shell_command("dart pub upgrade #{dependency.name}")
            yaml_content = File.read(yaml_file_name)
            lock_content = File.read(lock_file_name)
          end
        end

        {
          yaml: yaml_content,
          lock: lock_content
        }
      end

      def update_pubspec_yaml_file(new_req, updated_content)
        updated_content = SharedHelpers.in_a_temporary_directory do
          SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path.to_s,
            function: "file_updater",
            args: [
              "--type",
              "yaml",
              "--content",
              updated_content,
              "--dependency",
              dependency.name,
              "--version",
              dependency.version.to_s,
              "--requirement",
              JSON.dump(
                {
                  'requirement': new_req[:requirement],
                  'file': new_req[:file],
                  'groups': new_req[:groups],
                  'source': {
                    'type': new_req[:source][:type],
                    'url': new_req[:source][:url],
                    'path': new_req[:source][:path],
                    'ref': new_req[:source][:ref],
                    'resolved_ref': new_req[:source][:resolved_ref],
                    'relative': new_req[:source][:relative]
                  }
                }
              )
            ]
          )
        end

        updated_content
      end

      def update_pubspec_lock_file(new_req, updated_content)
        updated_content = SharedHelpers.in_a_temporary_directory do
          SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path.to_s,
            function: "file_updater",
            args: [
              "--type",
              "lock",
              "--content",
              updated_content,
              "--dependency",
              dependency.name,
              "--version",
              dependency.version,
              "--requirement",
              JSON.dump(
                {
                  'requirement': new_req[:requirement],
                  'file': new_req[:file],
                  'groups': new_req[:groups],
                  'source': {
                    'type': new_req[:source][:type],
                    'url': new_req[:source][:url],
                    'path': new_req[:source][:path],
                    'ref': new_req[:source][:ref],
                    'resolved_ref': new_req[:source][:resolved_ref],
                    'relative': new_req[:source][:relative]
                  }
                }
              )
            ]
          )
        end

        updated_content
      end

      # TODO: Check if we can make multi dependency updates work
      def dependency
        # Pub updates will only ever be updating a single dependency
        dependencies.first
      end

      def pubspec_file_pairs
        pairs = []
        pubspec_yaml_files.each do |f|
          lock_file = pubspec_lock_files.find { |l| f.directory == l.directory }
          next unless lock_file

          pairs << {
            yaml: f,
            lock: lock_file
          }
        end
        pairs
      end

      def pubspec_yaml_files
        dependency_files.select { |f| f.name.end_with?("pubspec.yaml") }
      end

      def pubspec_lock_files
        dependency_files.select { |f| f.name.end_with?("pubspec.lock") }
      end

      def check_required_files
        return if [*pubspec_yaml_files].any?

        raise "No pubspec.yaml configuration file!"
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("pub", Dependabot::Pub::FileUpdater)
