require "yaml"

# L7: Country alias map — normalize-only.
#
# Single choke point for every Country find_or_create site (UpsertLeagueTeams,
# UpsertPlayerCareer, UpdateTeam, Pl39Backfill, BravePlayerCareer). Raw API
# names resolve through `config/country_aliases.yml` (case-insensitive) to a
# canonical name; unmatched raw names still create a Country row as-is and log
# an `alias_missing` warn so a curator can seed the alias.
#
# Normalize-only: never renames or merges existing Country rows. Rows that
# collide on one canonical (e.g. "Brazil" + "Brasil", or case variants) are
# listed by `.forks` and reported by CoverageGate ("alias forks zero" is the
# acceptance state, curation happens outside the pipeline).
class CountryAlias < ApplicationService
  UNKNOWN = "Unknown"
  YML_FILENAME = "country_aliases.yml"

  class << self
    def config_path(config_dir = Rails.root.join("config"))
      Pathname.new(config_dir.to_s).join(YML_FILENAME)
    end

    # Raw alias map: downcased alias => canonical name. Memoized per path.
    def aliases(config_dir: Rails.root.join("config"))
      @aliases_by_path ||= {}
      key = File.expand_path(config_path(config_dir).to_s)
      @aliases_by_path.fetch(key) do
        @aliases_by_path[key] = load_aliases(config_path(config_dir))
      end
    end

    def reset!
      @aliases_by_path = {}
    end

    # Canonical name for a raw API value. Blank maps to Unknown; unmatched
    # raw names come back as-is (caller warns + still creates the row).
    def canonical_for(raw_name, config_dir: Rails.root.join("config"))
      raw = raw_name.to_s.strip
      return UNKNOWN if raw.empty?

      aliases(config_dir: config_dir)[raw.downcase] || raw
    end

    # True when the raw name is a known alias, an already-canonical value, or
    # the built-in Unknown fallback bucket (blank/"Unknown" never needs
    # curation, so it never warns).
    def matched?(raw_name, config_dir: Rails.root.join("config"))
      key = raw_name.to_s.strip.downcase
      return true if key.empty? || key == UNKNOWN.downcase

      map = aliases(config_dir: config_dir)
      return true if map.key?(key)

      map.values.any? { |canonical| canonical.to_s.strip.downcase == key }
    end

    # Normalize-then-find-or-create. Unmatched names warn `alias_missing` and
    # are kept verbatim so no data is ever dropped by normalization.
    def find_or_create!(raw_name, config_dir: Rails.root.join("config"))
      raw = raw_name.to_s.strip
      raw = UNKNOWN if raw.empty?
      canonical = canonical_for(raw, config_dir: config_dir)
      unless matched?(raw, config_dir: config_dir)
        Rails.logger.warn("CountryAlias alias_missing raw=#{raw.inspect} using=#{canonical.inspect}")
      end
      Country.find_or_create_by!(name: canonical)
    end

    # Forks: distinct Country rows that normalize to one canonical name.
    # Returns [{ canonical:, names: }] sorted by canonical, empty when clean.
    def forks(config_dir: Rails.root.join("config"))
      Country.distinct.pluck(:name)
        .group_by { |name| canonical_for(name, config_dir: config_dir).strip.downcase }
        .filter_map do |_key, names|
          uniq_names = names.uniq.sort
          next if uniq_names.size < 2

          { canonical: canonical_for(uniq_names.first, config_dir: config_dir), names: uniq_names }
        end
        .sort_by { |fork| fork[:canonical].to_s.downcase }
    end

    private

    # String-or-symbol tolerant, like Pl39Probe.read_yml: missing/unparseable
    # file means an empty map (every name unmatched, kept verbatim + warned).
    def load_aliases(path)
      return {} unless File.exist?(path.to_s)

      raw = YAML.safe_load(File.read(path.to_s)) || {}
      entries = raw["aliases"] || raw[:aliases] || {}
      return {} unless entries.is_a?(Hash)

      entries.to_h do |key, value|
        [ key.to_s.strip.downcase, value.to_s.strip ]
      end
    rescue Psych::SyntaxError
      {}
    end
  end
end
