import smtplib
from email.mime.text import MIMEText

# Email configuration
smtp_server = 'mail.lecaillon.com'
smtp_port = 587
username = 'anas'
password = '8769Jm04!'
sender_email = 'anas@lecaillon.com'
receiver_email = 'neosapien17@gmail.com'

# Create the email message
message = MIMEText("This is a test email to check DKIM headers.")
message['From'] = sender_email
message['To'] = receiver_email
message['Subject'] = 'Test Email for DKIM'

try:
    # Connect to the SMTP server
    with smtplib.SMTP(smtp_server, smtp_port) as server:
        server.starttls()  # Secure the connection
        server.login(username, password)

        # Send the email
        server.sendmail(sender_email, [receiver_email], message.as_string())
        print("Email sent successfully!")

except Exception as e:
    print(f"An error occurred: {e}")
