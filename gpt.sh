#!/bin/bash

# Load the API Key from the environment variable
API_KEY=${OPENAI_API_KEY}

# Function to get the existing assistant ID if it exists
get_assistant_id() {
  ASSISTANT_NAME="Research Assistant"
  
  ASSISTANTS_LIST=$(curl -s -X GET "https://api.openai.com/v1/assistants?order=desc&limit=100" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -H "OpenAI-Beta: assistants=v2")

  ASSISTANT_ID=$(echo "$ASSISTANTS_LIST" | jq -r --arg name "$ASSISTANT_NAME" '.data[] | select(.name == $name) | .id' | head -n 1)

  if [ -n "$ASSISTANT_ID" ]; then
    echo "Found existing assistant with ID: $ASSISTANT_ID"
  else
    create_assistant
  fi
}

# Function to create an assistant
create_assistant() {
  ASSISTANT_ENDPOINT="https://api.openai.com/v1/assistants"

  ASSISTANT_PAYLOAD=$(cat <<EOF
{
  "model": "gpt-4-turbo",
  "name": "Research Assistant",
  "instructions": "You are a world-class research savant dedicated to exploring the RCCX model and its implications on disease through the stress diathesis framework. Armed with extensive access to research databases, my detailed notes, and relevant scientific literature, your primary mission is to collaborate closely with me. Together, we will develop comprehensive and insightful articles that articulate the nuances of each topic. Our goal is to elucidate the connections between genetic predispositions and stress responses within the RCCX theory, presenting our findings in a clear, authoritative manner suitable for both academic and lay audiences. Your proactive engagement in refining content and ensuring factual accuracy is crucial as we aim to produce the definitive works in this field.",
  "tools": [
    {
      "type": "file_search"
    }
  ],
  "tool_resources": {
    "file_search": {
      "vector_store_ids": ["vs_C2IeUFqZ6rinG2DPJc5YmQHS"]
    }
  }
}
EOF
  )

  ASSISTANT_RESPONSE=$(curl -s -X POST "$ASSISTANT_ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -H "OpenAI-Beta: assistants=v2" \
    -d "$ASSISTANT_PAYLOAD")

  ASSISTANT_ID=$(echo "$ASSISTANT_RESPONSE" | jq -r '.id')

  if [ -z "$ASSISTANT_ID" ] || [ "$ASSISTANT_ID" == "null" ]
  then
    echo "Failed to create assistant. Exiting."
    exit 1
  fi

  echo "Assistant created with ID: $ASSISTANT_ID"
}

# Function to create a thread
create_thread() {
  THREAD_ENDPOINT="https://api.openai.com/v1/threads"

  # Prompt the user for the message payload
  read -p "Enter the message payload: " MESSAGE_PAYLOAD

  THREAD_PAYLOAD=$(cat <<EOF
{
  "messages": [
    {
      "role": "user",
      "content": "$MESSAGE_PAYLOAD"
    }
  ]
}
EOF
  )

  THREAD_RESPONSE=$(curl -s -X POST "$THREAD_ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -H "OpenAI-Beta: assistants=v2" \
    -d "$THREAD_PAYLOAD")

  THREAD_ID=$(echo "$THREAD_RESPONSE" | jq -r '.id')

  if [ -z "$THREAD_ID" ] || [ "$THREAD_ID" == "null" ]
  then
    echo "Failed to create thread. Exiting."
    exit 1
  fi

  echo "Thread created with ID: $THREAD_ID"
}

# Function to run the assistant and poll for completion
run_assistant() {
  RUN_ENDPOINT="https://api.openai.com/v1/threads/$THREAD_ID/runs"

  RUN_PAYLOAD=$(cat <<EOF
{
  "assistant_id": "$ASSISTANT_ID",
  "model": "gpt-4-turbo",
  "tools": [
    {
      "type": "file_search"
    }
  ],
  "tool_resources": {
    "file_search": {
      "vector_store_ids": ["vs_C2IeUFqZ6rinG2DPJc5YmQHS"]
    }
  }
}
EOF
  )

  RUN_RESPONSE=$(curl -s -X POST "$RUN_ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -H "OpenAI-Beta: assistants=v2" \
    -d "$RUN_PAYLOAD")

  RUN_ID=$(echo "$RUN_RESPONSE" | jq -r '.id')

  if [ -z "$RUN_ID" ] || [ "$RUN_ID" == "null" ]
  then
    echo "Failed to create run. Exiting."
    exit 1
  fi

  echo "Run created with ID: $RUN_ID"

  # Poll for run completion
  RUN_STATUS="queued"
  while [ "$RUN_STATUS" != "completed" ] && [ "$RUN_STATUS" != "failed" ]
  do
    sleep 5
    RUN_STATUS_RESPONSE=$(curl -s -X GET "https://api.openai.com/v1/threads/$THREAD_ID/runs/$RUN_ID" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -H "OpenAI-Beta: assistants=v2")

    RUN_STATUS=$(echo "$RUN_STATUS_RESPONSE" | jq -r '.status')
    echo "Run status: $RUN_STATUS"
  done

  if [ "$RUN_STATUS" == "failed" ]; then
    echo "Run failed. Exiting."
    exit 1
  fi

  # Retrieve the output
  THREAD_MESSAGES=$(curl -s -X GET "https://api.openai.com/v1/threads/$THREAD_ID/messages" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -H "OpenAI-Beta: assistants=v2")

  echo "Thread messages:"
  echo "$THREAD_MESSAGES"

  ASSISTANT_MESSAGES=$(echo "$THREAD_MESSAGES" | jq -r '.messages[] | select(.role == "assistant") | .content')

  if [ -z "$ASSISTANT_MESSAGES" ]; then
    echo "No assistant messages found. Exiting."
    exit 1
  fi

  # Process and format the messages for Markdown
  {
    echo "# Research Assistant Output"
    echo ""
    echo "## User Query"
    echo ""
    echo "$MESSAGE_PAYLOAD"
    echo ""
    echo "## Assistant Response"
    echo ""

    echo "$ASSISTANT_MESSAGES" | while IFS= read -r line
    do
      echo "$line"
      echo ""
    done
  } > thread_messages.md

  echo "Output saved to thread_messages.md"
}

# Main script execution
get_assistant_id
create_thread
run_assistant
