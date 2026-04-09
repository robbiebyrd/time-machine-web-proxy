FROM node:22-bookworm AS build

WORKDIR /app
COPY package.json ./
RUN npm install
COPY timemachine.ts ./
RUN npm run build

FROM node:22-bookworm-slim

WORKDIR /app
COPY --from=build /app/dist/timemachine.js ./
RUN addgroup --system timemachine && adduser --system --ingroup timemachine timemachine \
    && mkdir -p /app/cache && chown timemachine:timemachine /app/cache
USER timemachine

EXPOSE ${TIMEMACHINE_PORT:-8765}

CMD ["node", "timemachine.js"]
