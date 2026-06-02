FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart compile exe bin/kirill_api.dart -o bin/server

FROM scratch
WORKDIR /app
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server

EXPOSE 5195
CMD ["/app/bin/server"]
