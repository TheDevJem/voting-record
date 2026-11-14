import { createConsumer } from "@rails/actioncable";

// One shared WebSocket for the whole app. Connects lazily on the first subscription and reconnects on its own.
export const consumer = createConsumer("/cable");
