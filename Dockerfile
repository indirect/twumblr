FROM ruby:3.4.4-alpine AS base

ENV RACK_ENV="production" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT="1"

RUN gem update --system --no-document && \
    gem install -N bundler

FROM base AS build

RUN apk add build-base git yaml-dev
COPY Gemfile* .ruby-version .
RUN --mount=type=cache,id=bld-gem-cache,sharing=locked,target=/srv/bundle \
    bundle config path /srv/bundle && \
    bundle install && \
    bundle clean && \
		bundle show --paths && \
		mkdir -p /app/vendor  && \
		cp -r /srv/bundle /app/vendor/bundle

FROM base
WORKDIR /app
RUN apk add git
COPY --from=build /app/vendor/bundle /app/vendor/bundle
COPY Gemfile* .ruby-version /app
COPY lib /app/lib
COPY bin/web /app/bin/

CMD ["./bin/web"]
