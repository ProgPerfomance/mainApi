ок в#!/bin/bash

# API Test Script for Kirill API
# Make sure the server is running before executing this script

BASE_URL="http://localhost:8080/api/v1"

echo "=========================================="
echo "Testing Kirill API"
echo "=========================================="
echo ""

# 1. Register a new user
echo "1. Registering new user..."
REGISTER_RESPONSE=$(curl -s -X POST "${BASE_URL}/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test User",
    "email": "test@example.com",
    "password": "testpassword123",
    "referralCode": "REF123"
  }')

echo "Response: $REGISTER_RESPONSE"
echo ""

# Extract user ID from response
USER_ID=$(echo $REGISTER_RESPONSE | grep -o '"_id":"[^"]*' | cut -d'"' -f4)
echo "User ID: $USER_ID"
echo ""

# 2. Login
echo "2. Logging in..."
LOGIN_RESPONSE=$(curl -s -X POST "${BASE_URL}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "testpassword123"
  }')

echo "Response: $LOGIN_RESPONSE"
echo ""

# 3. Get profile
echo "3. Getting user profile..."
PROFILE_RESPONSE=$(curl -s -X POST "${BASE_URL}/auth/profile" \
  -H "Content-Type: application/json" \
  -d "{
    \"userId\": \"$USER_ID\"
  }")

echo "Response: $PROFILE_RESPONSE"
echo ""

# 4. Deposit balance
echo "4. Depositing balance..."
DEPOSIT_RESPONSE=$(curl -s -X POST "${BASE_URL}/billing/deposit" \
  -H "Content-Type: application/json" \
  -d "{
    \"userId\": \"$USER_ID\",
    \"amount\": 100.50,
    \"description\": \"Test deposit\"
  }")

echo "Response: $DEPOSIT_RESPONSE"
echo ""

# 5. Get profile again to check balance
echo "5. Checking updated balance..."
UPDATED_PROFILE=$(curl -s -X POST "${BASE_URL}/auth/profile" \
  -H "Content-Type: application/json" \
  -d "{
    \"userId\": \"$USER_ID\"
  }")

echo "Response: $UPDATED_PROFILE"
echo ""

echo "=========================================="
echo "Testing completed!"
echo "=========================================="

