# frozen_string_literal: true

require_relative 'lib/kommandant/version'

Gem::Specification.new do |spec|
  spec.name = 'kommandant'
  spec.version = Kommandant::VERSION
  spec.authors = ['himanshu']
  spec.email = ['hpanwar@g2.com']

  spec.summary = 'Herr Kommandant keeps you focused with German military discipline'
  spec.description = <<~DESC.tr("\n", ' ').strip
    A productivity enforcement gem that monitors your activity and delivers escalating
    German-accented warnings when you slack off. Features idle detection, app monitoring,
    browser tab checking, and a tiered punishment system from gentle nudges to full interventions.
  DESC
  spec.homepage = 'https://github.com/hpanwar09/kommandant'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/hpanwar09/kommandant'
  spec.metadata['rubygems_mfa_required'] = 'true'

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ .gitignore])
    end
  end
  spec.bindir = 'exe'
  spec.executables = ['kommandant']
  spec.require_paths = ['lib']

  spec.add_dependency 'pastel', '~> 0.8'
  spec.add_dependency 'thor', '~> 1.3'
end
