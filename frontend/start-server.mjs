import {
    GetSecretValueCommand,
    SecretsManagerClient,
} from "@aws-sdk/client-secrets-manager";

const secretId = process.env.AWS_SECRETS_ID;

if (!process.env.CLERK_SECRET_KEY && secretId) {
    const response = await new SecretsManagerClient({}).send(
        new GetSecretValueCommand({ SecretId: secretId }),
    );
    const secret = JSON.parse(response.SecretString ?? "{}");

    if (secret.CLERK_SECRET_KEY) {
        process.env.CLERK_SECRET_KEY = secret.CLERK_SECRET_KEY;
    }
}

if (!process.env.CLERK_SECRET_KEY) {
    throw new Error("CLERK_SECRET_KEY is required to start the frontend");
}

await import("./server.js");
