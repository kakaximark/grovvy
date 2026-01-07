#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <appName> [port] [options]"
    echo "Options:"
    echo "  --language <lang>      Programming language (java, python, node; default: java)"
    echo "  --java-home <path>     Path to JDK installation for Java (default: /usr/share/jdk-21.0.3)"
    echo "  --base-dir <path>      Base directory path (default: /data)"
    echo "  --xms <size>           Initial heap size for Java (default: 1024m)"
    echo "  --xmx <size>           Maximum heap size for Java (default: 1024m)"
    echo "  --xmn <size>           Young generation size for Java (default: 512m)"
    echo "  --jdwp                 Enable JDWP debugging for Java (uses transport=dt_socket,server=y,suspend=n,address=*:1<port>)"
    echo "  --log-file <path>      Log file path (e.g., /path/to/logfile.log)"
    echo "  --app-name <name>      Spring application name for Java"
    echo "  --server-port <port>   Server port for application"
    echo "  --app-file <file>      Application file to run (default: app.jar for Java, app.py for Python, app.js for Node.js)"
    echo "  --watch                Watch service until it starts listening on the specified port (timeout: 300s)"
    echo "  --shutdown             Shutdown the specified application and exit"
    echo "  Any additional arguments will be passed to the application command"
    echo "Examples:"
    echo "  $0 plugin-chain 8007 --jdwp"
    echo "  $0 movie-account-web 8007 --workspace /data/video-storage --language rust"
    echo "  $0 video-storage 8007 --jdwp --workspace /data/video-storage"
    echo "  $0 plugin-chain --language python --server-port 8000 --app-file main.py --config /data/config.yaml"
    exit 1
}

# Function to shutdown application
shutdown_app() {
    local app_name="$1"
    local app_file="$2"
    local base_dir="$3"
    echo "Shutting down ${app_name}..."
    
    # Find and kill processes matching the application
    local pids=$(ps -ef | grep "${app_name}" | grep -v $$ | grep -v grep | awk '{print $2}')
    if [ -n "$pids" ]; then
        echo "Found running processes with PIDs: $pids"
        for pid in $pids; do
            echo "Terminating process with PID: $pid"
            kill -TERM $pid
            sleep 2
            
            # Check if process is still running, force kill if necessary
            if ps -p $pid > /dev/null 2>&1; then
                echo "Process $pid still running, force killing..."
                kill -9 $pid
                
                # Wait until process is completely terminated (util-like effect)
                local wait_count=0
                local max_wait=120  # Maximum wait time in seconds
                while ps -p $pid > /dev/null 2>&1; do
                    if [ $wait_count -ge $max_wait ]; then
                        echo "Warning: Process $pid still exists after ${max_wait} seconds"
                        break
                    fi
                    sleep 1
                    wait_count=$((wait_count + 1))
                    echo "Waiting for process $pid to terminate... ($wait_count/${max_wait})"
                done
            fi
            
            # Final verification
            if ps -p $pid > /dev/null 2>&1; then
                echo "Warning: Failed to terminate process $pid"
            else
                echo "Process $pid successfully terminated"
            fi
        done
        echo "${app_name} shutdown completed"
    else
        echo "No running processes found for ${app_name}"
    fi
    exit 0
}

# Default values
LANGUAGE="java"
JAVA_HOME="/usr/local/jdk-21.0.3/"
BASE_DIR="/data"
XMS="1024m"
XMX="1024m"
XMN="512m"
WATCH=true
JDWP=false
LOG_FILE=""
port=""
APP_FILE=""  # Will be set based on language if not provided
LOG=false
SHUTDOWN=false

# Check if appName is provided
if [ -z "$1" ]; then
    usage
fi

appName="$1"
shift

# Check if next argument is a port number (numeric)
if [[ $1 =~ ^[0-9]+$ ]]; then
    port="$1"
    shift
fi

# Parse command-line arguments and collect remaining arguments
EXTRA_ARGS=()
JVM_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --language) LANGUAGE="$2"; shift 2 ;;
        --java-home) JAVA_HOME="$2"; shift 2 ;;
        --base-dir) BASE_DIR="$2"; shift 2 ;;
        --xms) XMS="$2"; shift 2 ;;
        --xmx) XMX="$2"; shift 2 ;;
        --xmn) XMN="$2"; shift 2 ;;
        --jdwp) JDWP=true; shift ;;
        --log-file) LOG_FILE="$2"; shift 2 ;;
        --log) LOG=true; shift ;;
        --watch) WATCH=true; shift ;;
        --shutdown) SHUTDOWN=true; shift ;;
        --app-name) JVM_ARGS+=("-Dspring.application.name=$2"); shift 2 ;;
        --server-port) port="$2"; JVM_ARGS+=("-Dserver.port=$2"); shift 2 ;;
        --app-file) APP_FILE="$2"; shift 2 ;;
        *) EXTRA_ARGS+=("$1"); shift ;;
    esac
done

# Set default APP_FILE based on language if not provided
[ -z "$APP_FILE" ] && case "$LANGUAGE" in
    java) APP_FILE="app.jar" ;;
    python) APP_FILE="app.py" ;;
    node) APP_FILE="app.js" ;;
    rust) APP_FILE="$appName" ;;
    *) echo "Error: Unsupported language ${LANGUAGE}, supported languages: java, python, node"; exit 1 ;;
esac

# If shutdown option is specified, shutdown the application and exit
if [ "$SHUTDOWN" = true ]; then
    shutdown_app "$appName"
fi

# Construct application directory
appDir="${BASE_DIR}/${appName}"

# Check if application directory exists
if [ ! -d "$appDir" ]; then
    echo "Error: Application directory ${appDir} does not exist"
    exit 1
fi

# Change to application directory
cd "${appDir}" || { echo "Error: Cannot change to directory ${appDir}"; exit 1; }

# Stop existing process
echo "Stopping existing process for ${appName}..."
pid=$(ps -ef | grep "${APP_FILE} ${appName}" | grep -v $$ | grep -v grep | awk '{print $2}')
if [ -n "$pid" ]; then
    kill -9 $pid
    echo "Process with PID ${pid} terminated"
else
    echo "No existing process found for ${appName}"
fi

sleep 3

# Start new process based on language
echo "Starting new process for ${appName}${port:+ on port ${port}}..."
case "$LANGUAGE" in
    java)
        # Check if JAVA_HOME exists
        if [ ! -d "$JAVA_HOME" ]; then
            echo "Error: JAVA_HOME directory ${JAVA_HOME} does not exist"
            exit 1
        fi

        # Build JVM arguments dynamically
        JVM_ARGS=()
        [ "$JDWP" = true ] && [ -n "$port" ] && JVM_ARGS+=("-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:1${port}")
        [ -n "$LOG_FILE" ] && JVM_ARGS+=("-Dlogging.file.name=${LOG_FILE}")
        [ -n "$port" ] && ! [[ "${JVM_ARGS[*]}" =~ "-Dserver.port" ]] && JVM_ARGS+=("-Dserver.port=${port}")
        [ ${#EXTRA_ARGS[@]} -gt 0 ] && JVM_ARGS+=("${EXTRA_ARGS[@]}")
        
        # Start Java process
        nohup "${JAVA_HOME}/bin/java" -Xms${XMS} -Xmx${XMX} -Xmn${XMN} \
            -jar \
            "${JVM_ARGS[@]}" \
            "${APP_FILE}" ${appName} >> $appDir/logs/app.log 2>/dev/null &
        ;;
    python)
        # Check if application file exists
        if [ ! -f "$APP_FILE" ]; then
            echo "Error: Python application file ${APP_FILE} does not exist"
            exit 1
        fi
        CMD=("python3" "${APP_FILE}")
        [ -n "$port" ] && CMD+=("--port=${port}")
        [ ${#EXTRA_ARGS[@]} -gt 0 ] && CMD+=("${EXTRA_ARGS[@]}")
        nohup "${CMD[@]}" >> /dev/null 2>/dev/null &
        ;;
    rust)
        chmod +x ${APP_FILE}
        RUST_LOG=debug
        if [ ! -f "$APP_FILE" ]; then
            echo "Error: rust application file ${APP_FILE} does not exist"
            exit 1
        fi
        CMD=("./${APP_FILE}")
        [ ${#EXTRA_ARGS[@]} -gt 0 ] && CMD+=("${EXTRA_ARGS[@]}")
        if [ "$LOG" = true ]; then
            nohup "${CMD[@]}" >> $appDir/app.log 2>&1 &
            
        else
            nohup "${CMD[@]}" >>/dev/null 2>/dev/null &
        fi
        ;;
    node)
        # Check if application file exists
        if [ ! -f "$APP_FILE" ]; then
            echo "Error: Node.js application file ${APP_FILE} does not exist"
            exit 1
        fi
        CMD=("node" "${APP_FILE}")
        [ -n "$port" ] && CMD+=("--port=${port}")
        [ ${#EXTRA_ARGS[@]} -gt 0 ] && CMD+=("${EXTRA_ARGS[@]}")
        if [ "$LOG" = true ]; then
            nohup "${CMD[@]}" >> $appDir/app-date +%F.log 2>&1 &
        else
            nohup "${CMD[@]}" >> /dev/null 2>/dev/null &

        fi
        ;;
    *)
        echo "Error: Unsupported language ${LANGUAGE}, supported languages: java, python, node"
        exit 1
        ;;
esac

new_pid=$!

echo "${appName} started${port:+ on port ${port}}, PID: ${new_pid}"
echo "You can check the process status using: ps -ef | grep ${appName}"

# If watch option is enabled, monitor the port
if [ "$WATCH" = true ] && [ -n "$port" ]; then
    echo "Monitoring port ${port}..."
    timeout=300
    interval=5
    elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if netstat -tuln | grep -q ":${port}" ; then
            echo "Service successfully started and listening on port ${port}"
            exit 0
        fi
        
        # 如果端口未监听，检查进程是否还在运行
        if ! ps -p $new_pid > /dev/null 2>&1; then
            echo "Error: Process ${new_pid} has exited unexpectedly"
            echo "Service failed to start properly"
            # 显示日志文件的最后几行（如果存在）
            if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
                echo "Last 20 lines of log file:"
                cat "${LOG_FILE}" | tail -n 20
            fi
            # 根据语言查找可能的日志文件
            case "$LANGUAGE" in
                rust)
                    if [ -f "$appDir/app.log" ]; then
                        echo "Last 20 lines of rust app log:"
                        tail -n 20 "$appDir/app.log"
                    fi
                    ;;
                node)
                    local node_log="$appDir/app-$(date +%F).log"
                    if [ -f "$node_log" ]; then
                        echo "Last 20 lines of node app log:"
                        tail -n 20 "$node_log"
                    fi
                    ;;
            esac
            exit 1
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    # 超时后的最终检查
    echo "Error: Service failed to listen on port ${port} within ${timeout} seconds"
    
    # 检查进程状态
    if ps -p $new_pid > /dev/null 2>&1; then
        echo "Process ${new_pid} is still running but not listening on port ${port}"
        echo "This might indicate a configuration issue or the service is starting slowly"
    else
        echo "Process ${new_pid} has exited"
        echo "Service failed to start properly"
        # 显示日志信息
        if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
            echo "Last 20 lines of log file:"
            cat "${LOG_FILE}" | tail -n 20
        fi
        # 根据语言查找可能的日志文件
        case "$LANGUAGE" in
            rust)
                if [ -f "$appDir/app.log" ]; then
                    echo "Last 20 lines of rust app log:"
                    tail -n 20 "$appDir/app.log"
                fi
                ;;
            node)
                local node_log="$appDir/app-$(date +%F).log"
                if [ -f "$node_log" ]; then
                    echo "Last 20 lines of node app log:"
                    tail -n 20 "$node_log"
                fi
                ;;
        esac
    fi
    
    exit 1
fi
