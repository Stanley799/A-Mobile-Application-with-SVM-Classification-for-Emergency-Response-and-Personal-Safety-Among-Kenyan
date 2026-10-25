import sys
import os
import argparse
import getpass
from firebase_admin import initialize_app, auth, firestore, credentials

def get_app():
    try:
        return firestore.client()
    except Exception:
        initialize_app(credentials.ApplicationDefault(), {'projectId': 'emergencyresponsesystem-166601'})
        return firestore.client()

def cmd_show(args):
    get_app()
    email = args.email
    print(f"Checking account for {email}...")
    try:
        user = auth.get_user_by_email(email)
        print(f"UID: {user.uid}")
        print(f"Email: {user.email}")
        claims = user.custom_claims or {}
        print(f"Custom Claims: {claims}")
        isAdmin = claims.get('role') == 'SystemAdmin'
        print(f"Is SystemAdmin: {isAdmin}")

        db = firestore.client()
        user_doc = db.collection('users').document(user.uid).get()
        if user_doc.exists:
            print(f"Users profile: {user_doc.to_dict()}")
        else:
            print("Users profile: None")

        resp_doc = db.collection('responders').document(user.uid).get()
        if resp_doc.exists:
            print(f"Responder record: {resp_doc.to_dict()}")
        else:
            print("Responder record: None")
    except Exception as e:
        print(f"Error finding user: {e}")

def cmd_set_password(args):
    get_app()
    email = args.email
    try:
        user = auth.get_user_by_email(email)
        pwd = getpass.getpass("Enter new password: ")
        auth.update_user(user.uid, password=pwd)
        print("Password updated successfully.")
    except Exception as e:
        print(f"Error updating password: {e}")

def cmd_reset_link(args):
    get_app()
    email = args.email
    try:
        link = auth.generate_password_reset_link(email)
        print(f"Password reset link: {link}")
    except Exception as e:
        print(f"Error generating reset link: {e}")

def cmd_delete(args):
    get_app()
    email = args.email
    confirm = input(f"Type email '{email}' to confirm deletion: ")
    if confirm != email:
        print("Confirmation failed. Aborted.")
        return
    try:
        user = auth.get_user_by_email(email)
        auth.delete_user(user.uid)
        db = firestore.client()
        db.collection('users').document(user.uid).delete()
        db.collection('responders').document(user.uid).delete()
        print("Account and records deleted successfully.")
    except Exception as e:
        print(f"Error deleting user: {e}")

def main():
    parser = argparse.ArgumentParser(description="Admin Recovery Tool")
    subparsers = parser.add_subparsers(dest="command")

    p_show = subparsers.add_parser("show")
    p_show.add_argument("--email", required=True)

    p_pwd = subparsers.add_parser("set-password")
    p_pwd.add_argument("--email", required=True)

    p_link = subparsers.add_parser("reset-link")
    p_link.add_argument("--email", required=True)

    p_del = subparsers.add_parser("delete")
    p_del.add_argument("--email", required=True)

    args = parser.parse_args()
    if args.command == "show":
        cmd_show(args)
    elif args.command == "set-password":
        cmd_set_password(args)
    elif args.command == "reset-link":
        cmd_reset_link(args)
    elif args.command == "delete":
        cmd_delete(args)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
