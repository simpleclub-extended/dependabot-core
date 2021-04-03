# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/pub"
require "dependabot/shared_helpers"
require "dependabot/pub/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Pub::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: requirements,
      package_manager: "pub"
    )
  end
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(name: "pubspec.yaml", content: pubspec_yaml_body),
      Dependabot::DependencyFile.new(name: "pubspec.lock", content: pubspec_lock_body)
    ]
  end
  let(:pubspec_yaml_body) do
    fixture("pubspec_yamlfiles", pubspec_fixture_name + ".yaml")
  end
  let(:pubspec_lock_body) do
    fixture("pubspec_lockfiles", pubspec_fixture_name + ".lock")
  end
  let(:pubspec_fixture_name) { "hosted" }

  let(:dependency_name) { "path" }
  let(:version) { "1.7.0" }
  let(:requirements) do
    [{ requirement: requirement, groups: [], file: "pubspec.yaml", source: source }]
  end
  let(:requirement) { nil }
  let(:source) do
    {
      type: "hosted",
      url: "https://pub.dartlang.org",
    }
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    context "with a git dependency" do
      let(:pubspec_fixture_name) { "git_ssh_with_ref" }
      let(:source) do
        {
          type: "git",
          url: "git@github.com:dart-lang/path.git",
          path: ".",
          branch: nil,
          ref: "1.7.0",
          resolved_ref: "10c778c799b2fc06036cbd0aa0e399ad4eb1ff5b"
        }
      end

      before do
        git_url = "https://github.com/dart-lang/path.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "pub-path-label"),
            headers: git_header
          )
      end

      it { is_expected.to eq(Gem::Version.new("1.8.0")) }
    end

    context "with a hosted dependency" do
      let(:pubspec_fixture_name) { "hosted" }
      let(:source) do
        {
          type: "hosted",
          url: "https://pub.dartlang.org"
        }
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return(fixture("pub_outdated", pubspec_fixture_name + ".json"))
      end

      it { is_expected.to eq(Gem::Version.new("2.1.0")) }
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    context "with a git dependency" do
      let(:pubspec_fixture_name) { "git_ssh_with_ref" }
      let(:source) do
        {
          type: "git",
          url: "git@github.com:dart-lang/path.git",
          branch: nil,
          ref: "1.7.0",
          resolved_ref: "10c778c799b2fc06036cbd0aa0e399ad4eb1ff5b"
        }
      end

      before do
        git_url = "https://github.com/dart-lang/path.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "pub-path-label"),
            headers: git_header
          )
      end

      it { is_expected.to eq(Gem::Version.new("1.8.0")) }
    end

    context "with a hosted dependency" do
      let(:pubspec_fixture_name) { "hosted" }
      let(:source) do
        {
          type: "hosted",
          url: "https://pub.dartlang.org"
        }
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return(fixture("pub_outdated", pubspec_fixture_name + ".json"))
      end

      it { is_expected.to eq(Gem::Version.new("1.8.0")) }
    end
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "with a git dependency" do
      let(:pubspec_fixture_name) { "git_ssh_with_ref" }
      let(:source) do
        {
          type: "git",
          url: "git@github.com:dart-lang/path.git",
          branch: nil,
          ref: "1.7.0",
          resolved_ref: "10c778c799b2fc06036cbd0aa0e399ad4eb1ff5b"
        }
      end

      before do
        git_url = "https://github.com/dart-lang/path.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "pub-path-label"),
            headers: git_header
          )
      end

      it { is_expected.to eq(true) }
    end

    context "with a registry dependency", :focus do
      let(:pubspec_fixture_name) { "hosted" }
      let(:source) do
        {
          type: "hosted",
          url: "https://pub.dartlang.org"
        }
      end
      let(:version) { nil }
      let(:requirement) { "> 1.7.0" }

      before do
        allow(checker).to receive(:latest_version).
          and_return(Gem::Version.new("1.8.0"))
      end

      it { is_expected.to eq(true) }

      # context "when the requirement is already up-to-date" do
      #   let(:requirement) { "> 1.8.0" }
      #   it { is_expected.to be_falsey }
      # end

      # context "when no requirements can be unlocked" do
      #   subject { checker.can_update?(requirements_to_unlock: :none) }
      #   it { is_expected.to be_falsey }
      # end
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    context "with a git dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/cloudposse/pub-null-label.git",
          branch: nil,
          ref: ref
        }
      end
      let(:ref) { "tags/0.3.7" }

      before do
        git_url = "https://github.com/cloudposse/pub-null-label.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "pub-null-label"),
            headers: git_header
          )
      end

      context "with a reference" do
        let(:ref) { "tags/0.3.7" }

        it "updates the reference" do
          expect(updated_requirements).
            to eq(
              [{
                requirement: nil,
                groups: [],
                file: "main.tf",
                source: {
                  type: "git",
                  url: "https://github.com/cloudposse/pub-null-label.git",
                  branch: nil,
                  ref: "tags/0.4.1"
                }
              }]
            )
        end
      end

      context "without a reference" do
        let(:ref) { nil }
        it { is_expected.to eq(requirements) }
      end

      context "with a git SHA as the latest version" do
        let(:ref) { "master" }
        it { is_expected.to eq(requirements) }
      end
    end

    context "with a registry dependency" do
      let(:source) do
        {
          type: "registry",
          registry_hostname: "registry.pub.io",
          module_identifier: "hashicorp/consul/aws"
        }
      end
      let(:requirement) { "~> 0.2.1" }

      before do
        allow(checker).to receive(:latest_version).
          and_return(Gem::Version.new("0.3.8"))
      end

      it "updates the requirement" do
        expect(updated_requirements).
          to eq(
            [{
              requirement: "~> 0.3.8",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "registry.pub.io",
                module_identifier: "hashicorp/consul/aws"
              }
            }]
          )
      end

      context "when the requirement is already up-to-date" do
        let(:requirement) { "~> 0.3.1" }
        it { is_expected.to eq(requirements) }
      end
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    subject { checker.requirements_unlocked_or_can_be? }

    it { is_expected.to eq(true) }

    context "with a source that came from an http proxy" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/cloudposse/pub-null-label.git",
          branch: nil,
          ref: "tags/0.3.7",
          proxy_url: "https://my.example.com"
        }
      end

      it { is_expected.to eq(false) }
    end
  end
end